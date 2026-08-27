import AppKit
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
}
