import Foundation

final class ClipboardHistoryStore {
    static let defaultCapacity = 10
    // Released in v1.0.0. Keep these stable across app renames and upgrades.
    // A future format change must migrate existing data before writing it.
    static let persistenceDomain = "local.luokun.ClipTen"
    static let historyKey = "clipboardHistory"

    private let defaults: UserDefaults
    private let storageKey: String
    private let capacity: Int

    private(set) var entries: [String]

    init(
        // The app's own bundle domain must use .standard. Creating a suite
        // with the current bundle identifier can return nil in a packaged app.
        // UpgradePersistenceTests pins Info.plist to the released domain.
        defaults: UserDefaults = .standard,
        storageKey: String = ClipboardHistoryStore.historyKey,
        capacity: Int = ClipboardHistoryStore.defaultCapacity
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.capacity = max(1, capacity)
        self.entries = Array(
            (defaults.stringArray(forKey: storageKey) ?? [])
                .prefix(max(1, capacity))
        )
    }

    @discardableResult
    func add(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let previousEntries = entries
        entries.removeAll { $0 == text }
        entries.insert(text, at: 0)

        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }

        guard entries != previousEntries else {
            return false
        }

        persist()
        return true
    }

    func clear() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(entries, forKey: storageKey)
    }
}
