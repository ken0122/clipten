import AppKit
import XCTest
@testable import ClipTen

final class ImageControllerTests: XCTestCase {
    @MainActor
    func testMenuStableIDAndTenthShortcutRestoreOriginalImage() async throws {
        let fixture = try HistoryTestFixture()
        let store = fixture.store()
        let png = try ClipboardImageProcessor.prepare(HistoryTestFixture.image(), format: .png)
        try store.add(png)
        for n in 1...9 { try store.add("记录 \(n)") }
        var presented: NSMenu?
        let app = AppDelegate(historyStore: store, pasteboard: fixture.pasteboard, historyMenuPresenter: { presented = $0 })
        await app.history.waitUntilIdle()
        app.requestHistoryMenu()
        await Task.yield()
        // requestHistoryMenu schedules the presenter on the next main-queue turn.
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let menu = try XCTUnwrap(presented)
        let imageItem = try XCTUnwrap(menu.items.first { $0.title == "图片 · 32×16" })
        XCTAssertNotNil(imageItem.image)
        XCTAssertEqual(imageItem.representedObject as? UUID, app.history.entries[9].id)
        app.copyHistoryEntry(at: 9)
        await app.history.waitUntilIdle()
        XCTAssertEqual(fixture.pasteboard.data(forType: .png), png.original)
        XCTAssertNil(fixture.pasteboard.string(forType: .fileURL))
        XCTAssertNil(fixture.pasteboard.string(forType: .string))
        XCTAssertEqual(app.history.entries.first?.image, png.metadata)
        app.history.capture(.text("new item changes positions"))
        await app.history.waitUntilIdle()
        app.copyHistoryItem(imageItem) // Retained menu item must resolve ID, not old position 10.
        await app.history.waitUntilIdle()
        XCTAssertEqual(fixture.pasteboard.data(forType: .png), png.original)
        XCTAssertEqual(app.history.entries.first?.image, png.metadata)
        let entries = app.history.entries
        app.checkClipboard() // Suppress own writes instead of recapturing a duplicate.
        await app.history.waitUntilIdle()
        XCTAssertEqual(app.history.entries, entries)
    }

    @MainActor
    func testTIFFCopyAndMissingImageDoNotDamageClipboardOrOtherEntries() async throws {
        let fixture = try HistoryTestFixture()
        let store = fixture.store()
        let tiff = try ClipboardImageProcessor.prepare(HistoryTestFixture.image(.tiff), format: .tiff)
        try store.add(tiff)
        try store.add("文字不丢失")
        let controller = HistoryController(store: store)
        await controller.waitUntilIdle()
        let id = try XCTUnwrap(controller.entries.last?.id)
        var success = false
        controller.copy(id: id, to: fixture.pasteboard, didWrite: { _ in }, completion: { success = $0 })
        await controller.waitUntilIdle()
        XCTAssertTrue(success)
        XCTAssertEqual(fixture.pasteboard.data(forType: .tiff), tiff.original)
        let consumable = try XCTUnwrap(NSImage(pasteboard: fixture.pasteboard))
        XCTAssertEqual(consumable.representations.first?.pixelsWide, 32)
        XCTAssertEqual(consumable.representations.first?.pixelsHigh, 16)
        try FileManager.default.removeItem(at: store.imagesURL.appendingPathComponent(tiff.metadata.filename))
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("do not replace", forType: .string)
        let baseline = fixture.pasteboard.changeCount
        controller.copy(id: id, to: fixture.pasteboard, didWrite: { _ in XCTFail("Must not write") }, completion: { success = $0 })
        await controller.waitUntilIdle()
        XCTAssertFalse(success)
        XCTAssertEqual(controller.issue, .imageUnavailable)
        XCTAssertTrue(controller.unavailable.contains(id))
        XCTAssertEqual(controller.entries.count, 2)
        XCTAssertEqual(fixture.pasteboard.changeCount, baseline)
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), "do not replace")
        let restarted = HistoryController(store: fixture.store())
        await restarted.waitUntilIdle()
        XCTAssertTrue(restarted.unavailable.contains(id))
        XCTAssertEqual(restarted.entries, controller.entries)
    }

    @MainActor
    func testClearInvalidatesPendingImageCopyAndQueuedCaptures() async throws {
        let fixture = try HistoryTestFixture()
        let disk = FaultHistoryDisk()
        let store = fixture.store(disk: disk)
        let image = try ClipboardImageProcessor.prepare(HistoryTestFixture.image(), format: .png)
        try store.add(image)
        let controller = HistoryController(store: store)
        await controller.waitUntilIdle()
        fixture.pasteboard.setString("untouched", forType: .string)
        let baseline = fixture.pasteboard.changeCount
        let started = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
        disk.blockNextImageRead(started: started, resume: resume)
        controller.copy(id: controller.entries[0].id, to: fixture.pasteboard,
                        didWrite: { _ in XCTFail("Stale copy wrote clipboard") }, completion: { _ in })
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        controller.capture(.text("queued before clear"))
        controller.clear()
        resume.signal()
        await controller.waitUntilIdle()
        XCTAssertTrue(controller.entries.isEmpty)
        XCTAssertTrue(fixture.store().entries.isEmpty)
        XCTAssertEqual(fixture.pasteboard.changeCount, baseline)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: store.imagesURL.path).isEmpty)
    }

    @MainActor
    func testExternalClipboardChangeCancelsSlowCopy() async throws {
        let fixture = try HistoryTestFixture()
        let disk = FaultHistoryDisk()
        let store = fixture.store(disk: disk)
        try store.add(ClipboardImageProcessor.prepare(HistoryTestFixture.image(), format: .png))
        try store.add("front")
        let controller = HistoryController(store: store)
        await controller.waitUntilIdle()
        let before = controller.entries
        let started = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
        disk.blockNextImageRead(started: started, resume: resume)
        controller.copy(id: before[1].id, to: fixture.pasteboard, didWrite: { _ in XCTFail("Stale write") }, completion: { XCTAssertFalse($0) })
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("new external copy", forType: .string)
        resume.signal()
        await controller.waitUntilIdle()
        XCTAssertEqual(controller.issue, .clipboardChanged)
        XCTAssertEqual(controller.entries, before)
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), "new external copy")
    }

    @MainActor
    func testCaptureOrderAndMenuDoNotReloadFullSizeImages() async throws {
        let fixture = try HistoryTestFixture()
        let disk = FaultHistoryDisk()
        let store = fixture.store(disk: disk)
        let image = try ClipboardImageProcessor.prepare(HistoryTestFixture.image(), format: .png)
        try store.add(image)
        let app = AppDelegate(historyStore: store, pasteboard: fixture.pasteboard, historyMenuPresenter: { _ in })
        await app.history.waitUntilIdle()
        XCTAssertEqual(disk.imageReadCount, 1)
        let baseline = fixture.pasteboard.changeCount
        for _ in 0..<10 { app.rebuildMenu() }
        XCTAssertEqual(disk.imageReadCount, 1)
        XCTAssertEqual(fixture.pasteboard.changeCount, baseline)
        let tiff = try HistoryTestFixture.image(.tiff)
        app.history.capture(.images([.init(format: .tiff, data: tiff)], rejectedIssue: nil))
        app.history.capture(.text("after image"))
        await app.history.waitUntilIdle()
        XCTAssertEqual(app.history.entries[0].text, "after image")
        XCTAssertEqual(app.history.entries[1].image?.format, .tiff)
        XCTAssertEqual(disk.imageReadCount, 1)
        app.history.capture(.rejected(.imageTooLarge))
        await app.history.waitUntilIdle()
        XCTAssertEqual(app.history.issue, .imageTooLarge)
        XCTAssertEqual(app.history.entries.count, 3)
    }

    @MainActor
    func testFailedClearShowsAlreadyCommittedQueuedCapture() async throws {
        let fixture = try HistoryTestFixture()
        let disk = FaultHistoryDisk()
        let store = fixture.store(disk: disk)
        try store.add("retained")
        let controller = HistoryController(store: store)
        await controller.waitUntilIdle()
        disk.failWrites(to: "history-v2.json")
        controller.clear()
        await controller.waitUntilIdle()
        XCTAssertEqual(controller.entries.compactMap(\.text), ["retained"])
        XCTAssertEqual(controller.issue, .storageWrite)
        XCTAssertFalse(controller.isClearing)
        disk.failWrites(to: nil)
        controller.capture(.text("can retry"))
        await controller.waitUntilIdle()
        XCTAssertEqual(controller.entries.first?.text, "can retry")
    }

    @MainActor
    func testEntryEvictedDuringImageLoadIsRestoredWithItsOriginalID() async throws {
        let fixture = try HistoryTestFixture()
        let disk = FaultHistoryDisk()
        let store = fixture.store(disk: disk)
        let image = try ClipboardImageProcessor.prepare(HistoryTestFixture.image(), format: .png)
        try store.add(image)
        for n in 1...9 { try store.add("\(n)") }
        let controller = HistoryController(store: store)
        await controller.waitUntilIdle()
        let selectedID = controller.entries[9].id
        let started = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
        disk.blockNextImageRead(started: started, resume: resume)
        controller.copy(id: selectedID, to: fixture.pasteboard, didWrite: { _ in }, completion: { XCTAssertTrue($0) })
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        controller.capture(.text("evicts the selected image before copy promotion"))
        resume.signal()
        await controller.waitUntilIdle()
        XCTAssertEqual(controller.entries.count, 10)
        XCTAssertEqual(controller.entries.first?.id, selectedID)
        XCTAssertEqual(fixture.pasteboard.data(forType: .png), image.original)
        XCTAssertEqual(try fixture.store().readImage(image.metadata), image.original)
    }
}
