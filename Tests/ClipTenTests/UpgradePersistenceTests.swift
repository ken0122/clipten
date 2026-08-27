import AppKit
import XCTest
@testable import ClipTen

final class UpgradePersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // Never read or modify the user's real clipboard history in tests.
        suiteName = "ClipTenUpgradeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private var legacyHistory: [String] {
        ["最新内容 📋", "  保留前后空格  ", "第一行\n第二行", "https://example.com/?q=中文"]
            + (5...10).map { "旧版记录-\($0)" }
    }

    private func seedLegacyHistory() {
        // Literal key and [String] format are the v1.0.0 contract, not values
        // derived from the new implementation (which could drift together).
        defaults.set(legacyHistory, forKey: "clipboardHistory")
        defaults.set(true, forKey: "unrelatedPreference")
    }

    func testStorageIdentityMatchesReleasedAppAndPackage() throws {
        XCTAssertEqual(ClipboardHistoryStore.persistenceDomain, "local.luokun.ClipTen")
        XCTAssertEqual(ClipboardHistoryStore.historyKey, "clipboardHistory")
        XCTAssertEqual(ClipboardHistoryStore.defaultCapacity, 10)

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "local.luokun.ClipTen")
    }

    func testLoadsReleasedFormatWithoutChangingAnyStoredValues() throws {
        seedLegacyHistory()
        let before = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        let store = ClipboardHistoryStore(defaults: reopenedDefaults)

        XCTAssertEqual(store.entries, legacyHistory)
        let after = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: after))
    }

    @MainActor
    func testRestartDoesNotEvictHistoryButNextCopyIsRecorded() {
        seedLegacyHistory()
        let store = ClipboardHistoryStore(defaults: defaults)
        let pasteboard = NSPasteboard(name: .init(suiteName))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("更新期间的剪贴板，不应挤掉历史", forType: .string)
        let delegate = AppDelegate(historyStore: store, pasteboard: pasteboard)

        delegate.prepareClipboardMonitoring()
        delegate.checkClipboard()

        XCTAssertEqual(store.entries, legacyHistory)
        XCTAssertEqual(defaults.stringArray(forKey: "clipboardHistory"), legacyHistory)

        pasteboard.clearContents()
        pasteboard.setString("启动后的新复制", forType: .string)
        delegate.checkClipboard()

        let expected = ["启动后的新复制"] + Array(legacyHistory.prefix(9))
        XCTAssertEqual(store.entries, expected)
        XCTAssertEqual(ClipboardHistoryStore(defaults: defaults).entries, expected)
        XCTAssertTrue(defaults.bool(forKey: "unrelatedPreference"))
    }

    @MainActor
    func testRestartDoesNotMoveAnExistingClipboardEntryToFront() {
        seedLegacyHistory()
        let store = ClipboardHistoryStore(defaults: defaults)
        let pasteboard = NSPasteboard(name: .init(suiteName))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString(legacyHistory[5], forType: .string)
        let delegate = AppDelegate(historyStore: store, pasteboard: pasteboard)

        delegate.prepareClipboardMonitoring()
        delegate.checkClipboard()

        XCTAssertEqual(store.entries, legacyHistory)
    }

    @MainActor
    func testFirstLaunchStillCapturesCurrentClipboard() {
        let store = ClipboardHistoryStore(defaults: defaults)
        let pasteboard = NSPasteboard(name: .init(suiteName))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("首次启动的内容", forType: .string)
        let delegate = AppDelegate(historyStore: store, pasteboard: pasteboard)

        delegate.prepareClipboardMonitoring()

        XCTAssertEqual(store.entries, ["首次启动的内容"])
    }
}
