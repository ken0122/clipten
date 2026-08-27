import Foundation

// Synchronous engine confined to HistoryWorker's serial queue in production.
// Tests own separate instances, preference domains, and temporary directories.
final class ClipboardHistoryStore: @unchecked Sendable {
    static let defaultCapacity = 10
    static let persistenceDomain = "local.luokun.ClipTen"
    static let historyKey = "clipboardHistory"
    static let migrationKey = "clipboardHistoryFormatVersion"
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(persistenceDomain, isDirectory: true)
    }

    struct Manifest: Codable, Equatable {
        var schemaVersion = 2
        var entries: [ClipboardEntry]
        // Durable tombstone repairs interruption before the old backup is cleared.
        var legacyBackupCleared = false
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let capacity: Int
    private let disk: any HistoryDisk
    let directory: URL
    var indexURL: URL { directory.appendingPathComponent("history-v2.json") }
    var imagesURL: URL { directory.appendingPathComponent("images", isDirectory: true) }
    private var manifest = Manifest(entries: [])
    private(set) var entries: [ClipboardEntry] = []
    private(set) var storageIssue: HistoryIssue?
    private(set) var cleanupIssue: HistoryIssue?
    var isReadOnly: Bool { storageIssue != nil }

    init(defaults: UserDefaults = .standard,
         storageKey: String = ClipboardHistoryStore.historyKey,
         capacity: Int = ClipboardHistoryStore.defaultCapacity,
         directory: URL = ClipboardHistoryStore.defaultDirectory,
         disk: any HistoryDisk = LocalHistoryDisk()) {
        self.defaults = defaults // Own bundle domain must use .standard, never a same-named suite.
        self.storageKey = storageKey
        self.capacity = min(Self.defaultCapacity, max(1, capacity))
        self.directory = directory.standardizedFileURL
        self.disk = disk
        do {
            try checkPaths()
            if disk.exists(indexURL) {
                manifest = try readManifest()
                entries = manifest.entries
            } else {
                guard defaults.integer(forKey: Self.migrationKey) != 2 else { throw HistoryIssue.storageRead }
                let legacy = defaults.stringArray(forKey: storageKey)
                guard defaults.object(forKey: storageKey) == nil || legacy != nil else { throw HistoryIssue.storageRead }
                entries = Array((legacy ?? []).prefix(self.capacity)).map { ClipboardEntry(content: .text($0)) }
                manifest = Manifest(entries: entries)
                try disk.createDirectory(self.directory)
                try disk.createDirectory(imagesURL)
                try disk.writeAtomically(JSONEncoder().encode(manifest), to: indexURL)
                guard try readManifest() == manifest else { throw HistoryIssue.storageRead }
            }
            if defaults.integer(forKey: Self.migrationKey) != 2 {
                defaults.set(2, forKey: Self.migrationKey)
            }
            if manifest.legacyBackupCleared { defaults.set([String](), forKey: storageKey) }
            cleanupImages()
        } catch { storageIssue = .storageRead }
    }

    @discardableResult
    func add(_ text: String) throws -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let entry = entries.first { $0.text == text } ?? ClipboardEntry(content: .text(text))
        return try insert(entry)
    }

    @discardableResult
    func add(_ image: PreparedClipboardImage) throws -> Bool {
        try ensureWritable()
        let entry = entries.first { $0.image == image.metadata }
            ?? ClipboardEntry(content: .image(image.metadata))
        let url = try imageURL(image.metadata)
        do {
            try disk.createDirectory(imagesURL)
            try disk.writeAtomically(image.original, to: url)
        } catch { throw HistoryIssue.storageWrite }
        return try insert(entry)
    }

    @discardableResult
    func promote(id: UUID) throws -> Bool {
        guard let entry = entries.first(where: { $0.id == id }) else { return false }
        return try insert(entry)
    }

    // A capture can evict the selected entry while its bytes are loading. Restore
    // that exact resolved entry (and original file), never a newly occupied slot.
    func restore(_ entry: ClipboardEntry, payload: ClipboardPayload) throws {
        try ensureWritable()
        if let image = entry.image {
            guard case .image(let data, let format) = payload, format == image.format,
                  data.count == image.byteCount, ClipboardImageProcessor.digest(data) == image.digest else {
                throw HistoryIssue.imageUnavailable
            }
            let url = try imageURL(image)
            do {
                try disk.createDirectory(imagesURL)
                try disk.writeAtomically(data, to: url)
            } catch { throw HistoryIssue.storageWrite }
        }
        _ = try insert(entry)
    }

    func clear() throws {
        var cleared = Manifest(entries: [])
        cleared.legacyBackupCleared = true
        try commit(cleared)
        defaults.set([String](), forKey: storageKey)
    }

    func readImage(_ image: ClipboardImage) throws -> Data {
        do {
            let data = try disk.read(imageURL(image), maximumBytes: ClipboardImageProcessor.maximumBytes)
            guard data.count == image.byteCount, ClipboardImageProcessor.digest(data) == image.digest else {
                throw HistoryIssue.imageUnavailable
            }
            return data
        } catch { throw HistoryIssue.imageUnavailable }
    }

    private func insert(_ entry: ClipboardEntry) throws -> Bool {
        try ensureWritable()
        let updated = Array(([entry] + entries.filter { $0.id != entry.id }).prefix(capacity))
        guard updated != entries else { return false }
        var next = manifest
        next.entries = updated
        try commit(next)
        return true
    }

    private func commit(_ next: Manifest) throws {
        try ensureWritable()
        do { try disk.writeAtomically(JSONEncoder().encode(next), to: indexURL) }
        catch { throw HistoryIssue.storageWrite }
        manifest = next
        entries = next.entries
        cleanupImages()
    }

    private func ensureWritable() throws {
        guard !isReadOnly else { throw HistoryIssue.readOnly }
        do {
            guard try readManifest() == manifest else { throw HistoryIssue.storageRead }
        } catch {
            storageIssue = .storageRead
            throw HistoryIssue.storageRead
        }
    }

    private func readManifest() throws -> Manifest {
        try checkPaths()
        let decoded = try JSONDecoder().decode(Manifest.self, from: disk.read(indexURL, maximumBytes: nil))
        guard decoded.schemaVersion == 2, decoded.entries.count <= Self.defaultCapacity,
              Set(decoded.entries.map(\.id)).count == decoded.entries.count,
              decoded.entries.allSatisfy({ $0.image?.isValid ?? true }) else { throw HistoryIssue.storageRead }
        return decoded
    }

    private func checkPaths() throws {
        guard !disk.isSymbolicLink(directory), !disk.isSymbolicLink(indexURL),
              !disk.isSymbolicLink(imagesURL) else { throw HistoryIssue.storageRead }
    }

    private func imageURL(_ image: ClipboardImage) throws -> URL {
        try checkPaths()
        guard image.isValid else { throw HistoryIssue.imageUnavailable }
        let url = imagesURL.appendingPathComponent(image.filename)
        guard !disk.isSymbolicLink(url) else { throw HistoryIssue.imageUnavailable }
        return url
    }

    private func cleanupImages() {
        cleanupIssue = nil
        do {
            try checkPaths()
            guard disk.exists(imagesURL) else { return }
            let referenced = Set(entries.compactMap { $0.image?.filename })
            for file in try disk.children(imagesURL) {
                // Only generated flat filenames are eligible; never recurse.
                let name = file.lastPathComponent
                let digest = file.deletingPathExtension().lastPathComponent
                guard ["png", "tiff"].contains(file.pathExtension), digest.count == 64,
                      digest.allSatisfy({ "0123456789abcdef".contains($0) }),
                      !referenced.contains(name) else { continue }
                guard !disk.isSymbolicLink(file), disk.isRegularFile(file) else { throw HistoryIssue.cleanupFailed }
                try disk.remove(file)
            }
        } catch { cleanupIssue = .cleanupFailed }
    }
}
