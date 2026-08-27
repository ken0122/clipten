import AppKit

private struct HistorySnapshot: Sendable {
    let entries: [ClipboardEntry]
    let thumbnails: [UUID: Data]
    let unavailable: Set<UUID>
    let issue: HistoryIssue?
    let isReadOnly: Bool
}

private struct ResolvedClipboardEntry: Sendable {
    let entry: ClipboardEntry
    let payload: ClipboardPayload
}

// All fields are accessed exclusively on HistoryController.queue.
private final class HistoryWorker: @unchecked Sendable {
    var store: ClipboardHistoryStore?
    var thumbnails: [UUID: Data] = [:]
    var unavailable: Set<UUID> = []

    func snapshot() -> HistorySnapshot {
        let store = store!
        let ids = Set(store.entries.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        unavailable.formIntersection(ids)
        for entry in store.entries {
            guard let image = entry.image, thumbnails[entry.id] == nil,
                  !unavailable.contains(entry.id) else { continue }
            do {
                let prepared = try ClipboardImageProcessor.prepare(store.readImage(image), format: image.format)
                thumbnails[entry.id] = prepared.thumbnail
            } catch { unavailable.insert(entry.id) }
        }
        return HistorySnapshot(entries: store.entries, thumbnails: thumbnails, unavailable: unavailable,
                               issue: store.storageIssue ?? store.cleanupIssue, isReadOnly: store.isReadOnly)
    }

    func capture(_ capture: ClipboardCapture) throws -> HistorySnapshot {
        let store = store!
        switch capture {
        case .text(let text): try store.add(text)
        case .rejected(let issue): throw issue
        case .images(let candidates, let rejectedIssue):
            var selected: PreparedClipboardImage?
            var issue = rejectedIssue
            for candidate in candidates {
                do {
                    selected = try ClipboardImageProcessor.prepare(candidate.data, format: candidate.format)
                    break
                } catch { issue = issue ?? (error as? HistoryIssue ?? .invalidImage) }
            }
            guard let selected else { throw issue ?? HistoryIssue.invalidImage }
            try store.add(selected)
            if let entry = store.entries.first(where: { $0.image == selected.metadata }) {
                thumbnails[entry.id] = selected.thumbnail
                unavailable.remove(entry.id)
            }
        }
        return snapshot()
    }

    func payload(id: UUID) throws -> ResolvedClipboardEntry {
        guard let entry = store!.entries.first(where: { $0.id == id }) else { throw HistoryIssue.imageUnavailable }
        switch entry.content {
        case .text(let text): return ResolvedClipboardEntry(entry: entry, payload: .text(text))
        case .image(let image):
            do {
                let data = try store!.readImage(image)
                // Metadata and hash were validated on capture/load. Recheck decoding
                // before clearing the user's clipboard if the file is now unavailable.
                _ = try ClipboardImageProcessor.prepare(data, format: image.format)
                return ResolvedClipboardEntry(entry: entry, payload: .image(data, image.format))
            } catch {
                unavailable.insert(id)
                thumbnails.removeValue(forKey: id)
                throw HistoryIssue.imageUnavailable
            }
        }
    }
}

@MainActor
final class HistoryController {
    private let queue = DispatchQueue(label: "local.luokun.ClipTen.history", qos: .userInitiated)
    private let worker = HistoryWorker()
    private var generation = 0
    private var copyRequest = 0
    private var operations = 0
    private var captures = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var readyActions: [@MainActor () -> Void] = []
    private(set) var entries: [ClipboardEntry] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]
    private(set) var unavailable: Set<UUID> = []
    private(set) var issue: HistoryIssue?
    private(set) var isLoading = true
    private(set) var isReadOnly = false
    private(set) var isClearing = false
    var onChange: (@MainActor () -> Void)?
    // Backpressure bounds retained clipboard buffers; polling retries the latest value.
    var canCapture: Bool { !isLoading && !isReadOnly && !isClearing && captures < 2 }

    init(store: ClipboardHistoryStore? = nil) {
        enqueue({ worker in
            worker.store = store ?? ClipboardHistoryStore()
            return worker.snapshot()
        }) { [weak self] result in
            guard let self else { return }
            self.apply(result)
            self.isLoading = false
            let actions = self.readyActions
            self.readyActions.removeAll()
            for action in actions { action() }
            self.onChange?()
        }
    }

    func whenReady(_ action: @escaping @MainActor () -> Void) {
        if isLoading { readyActions.append(action) } else { action() }
    }

    func capture(_ capture: ClipboardCapture) {
        guard canCapture else { return }
        let currentGeneration = generation
        captures += 1
        enqueue({ try $0.capture(capture) }) { [weak self] result in
            guard let self else { return }
            self.captures -= 1
            guard self.generation == currentGeneration else { return }
            self.apply(result)
        }
    }

    func clear() {
        guard !isLoading, !isReadOnly, !isClearing else { return }
        generation += 1
        copyRequest += 1
        isClearing = true
        onChange?()
        enqueue({ worker in
            do { try worker.store!.clear() }
            catch {
                // Earlier captures may have committed before the failed clear.
                // Return their current state rather than leaving the menu stale.
                let snapshot = worker.snapshot()
                return HistorySnapshot(entries: snapshot.entries, thumbnails: snapshot.thumbnails,
                    unavailable: snapshot.unavailable, issue: error as? HistoryIssue ?? .storageWrite,
                    isReadOnly: snapshot.isReadOnly)
            }
            worker.thumbnails.removeAll()
            worker.unavailable.removeAll()
            return worker.snapshot()
        }) { [weak self] result in
            self?.isClearing = false
            self?.apply(result)
        }
    }

    func copy(id: UUID, to pasteboard: NSPasteboard,
              didWrite: @escaping @MainActor (Int) -> Void,
              completion: @escaping @MainActor (Bool) -> Void) {
        guard !isLoading, !isClearing, entries.contains(where: { $0.id == id }) else { return }
        copyRequest += 1
        let request = copyRequest
        let currentGeneration = generation
        let originalChangeCount = pasteboard.changeCount
        enqueue({ try $0.payload(id: id) }) { [weak self] result in
            guard let self, self.generation == currentGeneration, self.copyRequest == request else { return }
            switch result {
            case .failure(let issue):
                if issue == .imageUnavailable { self.unavailable.insert(id); self.thumbnails.removeValue(forKey: id) }
                self.report(issue)
                completion(false)
            case .success(let resolved):
                guard pasteboard.changeCount == originalChangeCount else {
                    self.report(.clipboardChanged)
                    completion(false)
                    return
                }
                let item = NSPasteboardItem()
                let prepared: Bool
                switch resolved.payload {
                case .text(let text): prepared = item.setString(text, forType: .string)
                case .image(let data, let format): prepared = item.setData(data, forType: .init(format.pasteboardType))
                }
                guard prepared else { self.report(.clipboardWrite); completion(false); return }
                pasteboard.clearContents()
                guard pasteboard.writeObjects([item]) else {
                    didWrite(pasteboard.changeCount)
                    self.report(.clipboardWrite)
                    completion(false)
                    return
                }
                didWrite(pasteboard.changeCount)
                self.enqueue({ worker in
                    try worker.store!.restore(resolved.entry, payload: resolved.payload)
                    return worker.snapshot()
                }) { [weak self] promoted in
                    guard let self, self.generation == currentGeneration else { return }
                    self.apply(promoted)
                    if case .success = promoted { completion(true) } else { completion(false) }
                }
            }
        }
    }

    func waitUntilIdle() async {
        guard operations != 0 else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func report(_ issue: HistoryIssue) {
        self.issue = issue
        if issue == .storageRead || issue == .readOnly { isReadOnly = true }
        onChange?()
    }

    private func apply(_ result: Result<HistorySnapshot, HistoryIssue>) {
        switch result {
        case .failure(let issue): report(issue)
        case .success(let snapshot):
            entries = snapshot.entries
            unavailable = snapshot.unavailable
            isReadOnly = snapshot.isReadOnly
            issue = snapshot.issue
            thumbnails = snapshot.thumbnails.compactMapValues { data in
                guard let image = NSImage(data: data) else { return nil }
                let ratio = 24 / max(image.size.width, image.size.height)
                image.size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
                return image
            }
            onChange?()
        }
    }

    private func enqueue<Value: Sendable>(
        _ operation: @escaping @Sendable (HistoryWorker) throws -> Value,
        completion: @escaping @MainActor (Result<Value, HistoryIssue>) -> Void
    ) {
        operations += 1
        let worker = worker
        queue.async { [weak self] in
            let result: Result<Value, HistoryIssue>
            do { result = .success(try autoreleasepool { try operation(worker) }) }
            catch { result = .failure(error as? HistoryIssue ?? .storageWrite) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                completion(result)
                self.operations -= 1
                if self.operations == 0 {
                    let waiters = self.idleWaiters
                    self.idleWaiters.removeAll()
                    for waiter in waiters { waiter.resume() }
                }
            }
        }
    }
}
