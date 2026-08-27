import AppKit
import Carbon.HIToolbox
import ClipTenDesign
import XCTest
@testable import ClipTen

final class ClipboardHistoryStoreTests: XCTestCase {
    func testKeepsOnlyTenNewestEntries() throws {
        let fixture = try HistoryTestFixture()
        let store = fixture.store()
        for number in 1...12 { try store.add("item-\(number)") }
        XCTAssertEqual(store.entries.count, 10)
        XCTAssertEqual(store.entries.first?.text, "item-12")
        XCTAssertEqual(store.entries.last?.text, "item-3")
    }

    func testDuplicateMovesToFrontWithoutGrowingHistory() throws {
        let fixture = try HistoryTestFixture()
        let store = fixture.store()
        try store.add("first")
        let id = store.entries[0].id
        try store.add("second")
        try store.add("first")
        XCTAssertEqual(store.entries.compactMap(\.text), ["first", "second"])
        XCTAssertEqual(store.entries[0].id, id)
    }

    func testIgnoresWhitespaceOnlyText() throws {
        let fixture = try HistoryTestFixture()
        let store = fixture.store()
        XCTAssertFalse(try store.add("  \n\t "))
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testPersistsAndClearsEntries() throws {
        let fixture = try HistoryTestFixture()
        try fixture.store().add("persisted")
        let restored = fixture.store()
        XCTAssertEqual(restored.entries.compactMap(\.text), ["persisted"])
        try restored.clear()
        XCTAssertTrue(fixture.store().entries.isEmpty)
    }

    @MainActor
    func testSelectingHistoryItemWritesItsTextToPasteboard() async throws {
        let fixture = try HistoryTestFixture()
        let store = fixture.store()
        try store.add("selected clipboard text")
        let delegate = AppDelegate(historyStore: store, pasteboard: fixture.pasteboard)
        await delegate.history.waitUntilIdle()
        let item = NSMenuItem(title: "preview", action: nil, keyEquivalent: "")
        item.representedObject = delegate.history.entries[0].id
        delegate.copyHistoryItem(item)
        await delegate.history.waitUntilIdle()
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), "selected clipboard text")
        XCTAssertEqual(delegate.history.entries.first?.text, "selected clipboard text")
    }

    func testStatusIconIsAnEighteenPointTemplateImage() {
        let image = ClipTenIcon.statusImage()
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
    }

    @MainActor
    func testGlobalShortcutsUseAllNumberKeysWithUncommonModifiers() {
        let definitions = GlobalShortcutManager.definitions
        XCTAssertEqual(definitions.map(\.slot), Array(0..<10))
        XCTAssertEqual(Set(definitions.map(\.keyCode)).count, 10)
        XCTAssertEqual(GlobalShortcutManager.modifierFlags, UInt32(controlKey | shiftKey))
        XCTAssertEqual(GlobalShortcutManager.modifierFlags & UInt32(cmdKey | optionKey), 0)
    }

    @MainActor
    func testGlobalShortcutSelectionCopiesWithoutOpeningMenu() async throws {
        let fixture = try HistoryTestFixture()
        let store = fixture.store()
        try store.add("older")
        try store.add("newest")
        let delegate = AppDelegate(historyStore: store, pasteboard: fixture.pasteboard)
        await delegate.history.waitUntilIdle()
        delegate.copyHistoryEntry(at: 1)
        await delegate.history.waitUntilIdle()
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), "older")
        XCTAssertEqual(delegate.history.entries.first?.text, "older")
    }
}
