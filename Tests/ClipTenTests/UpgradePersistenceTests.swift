import AppKit
import XCTest
@testable import ClipTen

final class UpgradePersistenceTests: XCTestCase {
    private let legacy = ["最新内容 📋", "  保留前后空格  ", "第一行\n第二行", "https://example.com/?q=中文"]
        + (5...10).map { "旧版记录-\($0)" }

    func testStorageIdentityMatchesReleasedAppAndPackage() throws {
        XCTAssertEqual(ClipboardHistoryStore.persistenceDomain, "local.luokun.ClipTen")
        XCTAssertEqual(ClipboardHistoryStore.historyKey, "clipboardHistory")
        XCTAssertEqual(ClipboardHistoryStore.defaultCapacity, 10)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "local.luokun.ClipTen")
    }

    func testLoadsReleasedFormatWithoutChangingLegacyValues() throws {
        let fixture = try HistoryTestFixture()
        fixture.defaults.set(legacy, forKey: "clipboardHistory")
        fixture.defaults.set(true, forKey: "unrelatedPreference")
        let store = fixture.store()
        XCTAssertFalse(store.isReadOnly)
        XCTAssertEqual(store.entries.compactMap(\.text), legacy)
        XCTAssertEqual(fixture.defaults.stringArray(forKey: "clipboardHistory"), legacy)
        XCTAssertTrue(fixture.defaults.bool(forKey: "unrelatedPreference"))
        XCTAssertEqual(fixture.defaults.integer(forKey: ClipboardHistoryStore.migrationKey), 2)
        let index = try Data(contentsOf: store.indexURL)
        XCTAssertEqual(fixture.store().entries, store.entries)
        XCTAssertEqual(try Data(contentsOf: store.indexURL), index)
    }

    @MainActor
    func testRestartDoesNotEvictHistoryButNextCopyIsRecorded() async throws {
        let fixture = try HistoryTestFixture()
        fixture.defaults.set(legacy, forKey: "clipboardHistory")
        let store = fixture.store()
        fixture.pasteboard.setString("更新期间的剪贴板，不应挤掉历史", forType: .string)
        let delegate = AppDelegate(historyStore: store, pasteboard: fixture.pasteboard)
        await delegate.history.waitUntilIdle()
        delegate.prepareClipboardMonitoring()
        delegate.checkClipboard()
        await delegate.history.waitUntilIdle()
        XCTAssertEqual(delegate.history.entries.compactMap(\.text), legacy)
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("启动后的新复制", forType: .string)
        delegate.checkClipboard()
        await delegate.history.waitUntilIdle()
        let expected = ["启动后的新复制"] + Array(legacy.prefix(9))
        XCTAssertEqual(delegate.history.entries.compactMap(\.text), expected)
        XCTAssertEqual(fixture.store().entries.compactMap(\.text), expected)
    }

    @MainActor
    func testRestartDoesNotMoveAnExistingClipboardEntryToFront() async throws {
        let fixture = try HistoryTestFixture()
        fixture.defaults.set(legacy, forKey: "clipboardHistory")
        fixture.pasteboard.setString(legacy[5], forType: .string)
        let delegate = AppDelegate(historyStore: fixture.store(), pasteboard: fixture.pasteboard)
        await delegate.history.waitUntilIdle()
        delegate.prepareClipboardMonitoring()
        delegate.checkClipboard()
        await delegate.history.waitUntilIdle()
        XCTAssertEqual(delegate.history.entries.compactMap(\.text), legacy)
    }

    @MainActor
    func testFirstLaunchWaitsForANewCopy() async throws {
        let fixture = try HistoryTestFixture()
        fixture.pasteboard.setString("首次启动的内容", forType: .string)
        let delegate = AppDelegate(historyStore: fixture.store(), pasteboard: fixture.pasteboard)
        await delegate.history.waitUntilIdle()
        delegate.prepareClipboardMonitoring()
        await delegate.history.waitUntilIdle()
        XCTAssertTrue(delegate.history.entries.isEmpty)
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("首次启动的内容", forType: .string)
        delegate.checkClipboard()
        await delegate.history.waitUntilIdle()
        XCTAssertEqual(delegate.history.entries.compactMap(\.text), ["首次启动的内容"])
    }

    @MainActor
    func testClearThenRestartNeverRecapturesUnchangedSystemClipboard() async throws {
        let fixture = try HistoryTestFixture()
        let store = fixture.store()
        try store.add("cleared text still on clipboard")
        fixture.pasteboard.setString("cleared text still on clipboard", forType: .string)
        try store.clear()
        let delegate = AppDelegate(historyStore: fixture.store(), pasteboard: fixture.pasteboard)
        await delegate.history.waitUntilIdle()
        delegate.prepareClipboardMonitoring()
        delegate.checkClipboard()
        await delegate.history.waitUntilIdle()
        XCTAssertTrue(delegate.history.entries.isEmpty)
        XCTAssertTrue(fixture.store().entries.isEmpty)
    }

    func testMigrationFailureAndInterruptedMarkerDoNotLoseLegacy() throws {
        let fixture = try HistoryTestFixture()
        fixture.defaults.set(legacy, forKey: "clipboardHistory")
        let disk = FaultHistoryDisk()
        disk.failWrites(to: "history-v2.json")
        let failed = fixture.store(disk: disk)
        XCTAssertTrue(failed.isReadOnly)
        XCTAssertEqual(failed.entries.compactMap(\.text), legacy)
        XCTAssertEqual(fixture.defaults.integer(forKey: ClipboardHistoryStore.migrationKey), 0)
        disk.failWrites(to: nil)
        let recovered = fixture.store(disk: disk)
        fixture.defaults.removeObject(forKey: ClipboardHistoryStore.migrationKey)
        XCTAssertEqual(fixture.store().entries, recovered.entries)
        XCTAssertEqual(fixture.defaults.stringArray(forKey: "clipboardHistory"), legacy)
    }

    func testCorruptOrMissingMigratedIndexIsNeverRecreated() throws {
        let fixture = try HistoryTestFixture()
        fixture.defaults.set(legacy, forKey: "clipboardHistory")
        let index = fixture.store().indexURL
        let invalid = Data("broken index".utf8)
        try invalid.write(to: index)
        let corrupt = fixture.store()
        XCTAssertTrue(corrupt.isReadOnly)
        XCTAssertThrowsError(try corrupt.add("must not overwrite"))
        XCTAssertEqual(try Data(contentsOf: index), invalid)
        try FileManager.default.removeItem(at: index)
        XCTAssertTrue(fixture.store().isReadOnly)
        XCTAssertFalse(FileManager.default.fileExists(atPath: index.path))
    }

    func testClearTombstonePreventsLegacyResurrection() throws {
        let fixture = try HistoryTestFixture()
        fixture.defaults.set(legacy, forKey: "clipboardHistory")
        let store = fixture.store()
        try store.clear()
        // Simulate interruption before the old preference backup was cleared.
        fixture.defaults.set(legacy, forKey: "clipboardHistory")
        let restored = fixture.store()
        XCTAssertTrue(restored.entries.isEmpty)
        XCTAssertEqual(fixture.defaults.stringArray(forKey: "clipboardHistory"), [])
    }

    func testMigrationReadbackFailureDoesNotMarkCompleteAndCanResume() throws {
        let fixture = try HistoryTestFixture()
        fixture.defaults.set(legacy, forKey: "clipboardHistory")
        let disk = FaultHistoryDisk()
        disk.failReads(from: "history-v2.json")
        let failed = fixture.store(disk: disk)
        XCTAssertTrue(failed.isReadOnly)
        XCTAssertEqual(failed.entries.compactMap(\.text), legacy)
        XCTAssertEqual(fixture.defaults.integer(forKey: ClipboardHistoryStore.migrationKey), 0)
        XCTAssertEqual(fixture.defaults.stringArray(forKey: "clipboardHistory"), legacy)
        disk.failReads(from: nil)
        XCTAssertEqual(fixture.store(disk: disk).entries.compactMap(\.text), legacy)
        XCTAssertEqual(fixture.defaults.integer(forKey: ClipboardHistoryStore.migrationKey), 2)
    }

    func testLiveIndexDamageLocksWritesAndKeepsInMemoryHistory() throws {
        let fixture = try HistoryTestFixture()
        let store = fixture.store()
        try store.add("must survive")
        let before = store.entries
        let invalid = Data("invalid while running".utf8)
        try invalid.write(to: store.indexURL)
        XCTAssertThrowsError(try store.add("new"))
        XCTAssertTrue(store.isReadOnly)
        XCTAssertEqual(store.entries, before)
        XCTAssertEqual(try Data(contentsOf: store.indexURL), invalid)
    }

    func testSymlinkedRootIsNotReadOrWritten() throws {
        let fixture = try HistoryTestFixture()
        let outside = fixture.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.directory, withDestinationURL: outside)
        let store = fixture.store()
        XCTAssertTrue(store.isReadOnly)
        XCTAssertThrowsError(try store.add("must not escape"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
}
