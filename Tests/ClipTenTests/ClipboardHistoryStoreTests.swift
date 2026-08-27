import AppKit
import Carbon.HIToolbox
import ClipTenDesign
import XCTest
@testable import ClipTen

final class ClipboardHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ClipTenTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testKeepsOnlyTenNewestEntries() {
        let store = ClipboardHistoryStore(defaults: defaults)

        for number in 1...12 {
            store.add("item-\(number)")
        }

        XCTAssertEqual(store.entries.count, 10)
        XCTAssertEqual(store.entries.first, "item-12")
        XCTAssertEqual(store.entries.last, "item-3")
    }

    func testDuplicateMovesToFrontWithoutGrowingHistory() {
        let store = ClipboardHistoryStore(defaults: defaults)
        store.add("first")
        store.add("second")
        store.add("first")

        XCTAssertEqual(store.entries, ["first", "second"])
    }

    func testIgnoresWhitespaceOnlyText() {
        let store = ClipboardHistoryStore(defaults: defaults)

        XCTAssertFalse(store.add("  \n\t "))
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testPersistsAndClearsEntries() {
        let firstStore = ClipboardHistoryStore(defaults: defaults)
        firstStore.add("persisted")

        let restoredStore = ClipboardHistoryStore(defaults: defaults)
        XCTAssertEqual(restoredStore.entries, ["persisted"])

        restoredStore.clear()
        let emptyStore = ClipboardHistoryStore(defaults: defaults)
        XCTAssertTrue(emptyStore.entries.isEmpty)
    }

    @MainActor
    func testSelectingHistoryItemWritesItsTextToPasteboard() {
        let pasteboard = NSPasteboard(name: .init("ClipTenTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let store = ClipboardHistoryStore(defaults: defaults)
        let delegate = AppDelegate(historyStore: store, pasteboard: pasteboard)
        let menuItem = NSMenuItem(title: "preview", action: nil, keyEquivalent: "")
        menuItem.representedObject = "selected clipboard text"

        delegate.copyHistoryItem(menuItem)

        XCTAssertEqual(pasteboard.string(forType: .string), "selected clipboard text")
        XCTAssertEqual(store.entries.first, "selected clipboard text")
    }

    func testStatusIconIsAnEighteenPointTemplateImage() {
        let image = ClipTenIcon.statusImage()

        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
    }

    @MainActor
    func testGlobalShortcutsUseAllNumberKeysWithUncommonModifiers() {
        let definitions = GlobalShortcutManager.definitions
        let modifierFlags = GlobalShortcutManager.modifierFlags

        XCTAssertEqual(definitions.map(\.slot), Array(0..<10))
        XCTAssertEqual(Set(definitions.map(\.keyCode)).count, 10)
        XCTAssertEqual(modifierFlags, UInt32(controlKey | shiftKey))
        XCTAssertEqual(modifierFlags & UInt32(cmdKey | optionKey), 0)
    }

    @MainActor
    func testGlobalShortcutSelectionCopiesWithoutOpeningMenu() {
        let pasteboard = NSPasteboard(name: .init("ClipTenTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let store = ClipboardHistoryStore(defaults: defaults)
        store.add("older")
        store.add("newest")
        let delegate = AppDelegate(historyStore: store, pasteboard: pasteboard)

        delegate.copyHistoryEntry(at: 1)

        XCTAssertEqual(pasteboard.string(forType: .string), "older")
        XCTAssertEqual(store.entries.first, "older")
    }
}
