import AppKit
import ImageIO
import XCTest
@testable import ClipTen

final class ImageHistoryTests: XCTestCase {
    func testPNGAndTIFFKeepOriginalBytesAndAlphaWithBoundedThumbnail() throws {
        for format in [ClipboardImageFormat.png, .tiff] {
            let raw = try HistoryTestFixture.image(format, width: 320, height: 160)
            let image = try ClipboardImageProcessor.prepare(raw, format: format)
            XCTAssertEqual(image.original, raw)
            XCTAssertEqual(image.metadata.width, 320)
            XCTAssertEqual(image.metadata.height, 160)
            XCTAssertEqual(image.metadata.byteCount, raw.count)
            XCTAssertTrue(image.metadata.isValid)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(raw as CFData, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertNotEqual(decoded.alphaInfo, .none)
            let preview = try XCTUnwrap(CGImageSourceCreateWithData(image.thumbnail as CFData, nil))
            let thumb = try XCTUnwrap(CGImageSourceCreateImageAtIndex(preview, 0, nil))
            XCTAssertEqual(thumb.width, 48)
            XCTAssertEqual(thumb.height, 24)
        }
    }

    func testLimitsMalformedAndMultipageImages() throws {
        XCTAssertThrowsError(try ClipboardImageProcessor.prepare(
            Data(count: ClipboardImageProcessor.maximumBytes + 1), format: .png)) {
            XCTAssertEqual($0 as? HistoryIssue, .imageTooLarge)
        }
        for raw in [Data(), Data("not an image".utf8), Data(try HistoryTestFixture.image().prefix(20))] {
            XCTAssertThrowsError(try ClipboardImageProcessor.prepare(raw, format: .png))
        }
        XCTAssertThrowsError(try ClipboardImageProcessor.prepare(HistoryTestFixture.image(.png), format: .tiff))
        XCTAssertThrowsError(try ClipboardImageProcessor.prepare(HistoryTestFixture.image(.tiff, frames: 2), format: .tiff)) {
            XCTAssertEqual($0 as? HistoryIssue, .unsupportedImage)
        }
        // Highly compressible valid image exceeds pixels, not bytes.
        let huge = try HistoryTestFixture.image(width: 8000, height: 5001)
        XCTAssertLessThan(huge.count, ClipboardImageProcessor.maximumBytes)
        XCTAssertThrowsError(try ClipboardImageProcessor.prepare(huge, format: .png)) {
            XCTAssertEqual($0 as? HistoryIssue, .imageTooLarge)
        }
        let digest = String(repeating: "a", count: 64)
        XCTAssertTrue(ClipboardImage(format: .png, digest: digest, width: 8000, height: 5000, byteCount: 20_000_000).isValid)
        XCTAssertFalse(ClipboardImage(format: .png, digest: digest, width: Int.max, height: Int.max, byteCount: 1).isValid)
    }

    func testMixedCapacityDeduplicationPersistenceAndCleanup() throws {
        let fixture = try HistoryTestFixture()
        let store = fixture.store()
        let png = try ClipboardImageProcessor.prepare(HistoryTestFixture.image(), format: .png)
        let tiff = try ClipboardImageProcessor.prepare(HistoryTestFixture.image(.tiff), format: .tiff)
        try store.add(png)
        let pngID = try XCTUnwrap(store.entries.first?.id)
        try store.add(tiff) // Different format/encoding remains a separate entry.
        for n in 1...9 { try store.add("中文 \(n)\n<&> 📋") }
        XCTAssertEqual(store.entries.count, 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imagesURL.appendingPathComponent(png.metadata.filename).path))
        try store.add(png)
        let restoredID = try XCTUnwrap(store.entries.first?.id)
        XCTAssertNotEqual(restoredID, pngID) // It was evicted, then captured again.
        try store.add("other")
        try store.add(png)
        XCTAssertEqual(store.entries.first?.id, restoredID)
        XCTAssertEqual(store.entries.filter { $0.image == png.metadata }.count, 1)
        let restarted = fixture.store()
        XCTAssertEqual(restarted.entries, store.entries)
        XCTAssertEqual(try restarted.readImage(png.metadata), png.original)
        try restarted.clear()
        XCTAssertTrue(fixture.store().entries.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: store.imagesURL.path).isEmpty)
        XCTAssertEqual(fixture.defaults.stringArray(forKey: ClipboardHistoryStore.historyKey), [])
    }

    func testFailedWritesNeverEvictOrDeleteCommittedImages() throws {
        let fixture = try HistoryTestFixture()
        let disk = FaultHistoryDisk()
        let store = fixture.store(disk: disk)
        let image = try ClipboardImageProcessor.prepare(HistoryTestFixture.image(), format: .png)
        try store.add(image)
        for n in 1...9 { try store.add("\(n)") }
        let before = store.entries
        let bytes = try Data(contentsOf: store.indexURL)
        disk.failWrites(to: "history-v2.json")
        XCTAssertThrowsError(try store.add("would evict image"))
        XCTAssertThrowsError(try store.clear())
        XCTAssertEqual(store.entries, before)
        XCTAssertEqual(try Data(contentsOf: store.indexURL), bytes)
        XCTAssertEqual(try store.readImage(image.metadata), image.original)
        let second = try ClipboardImageProcessor.prepare(HistoryTestFixture.image(red: 0.9), format: .png)
        XCTAssertThrowsError(try store.add(second))
        XCTAssertEqual(store.entries, before)
        disk.failWrites(to: second.metadata.filename)
        XCTAssertThrowsError(try store.add(second))
        XCTAssertEqual(store.entries, before)
        disk.failWrites(to: nil)
        disk.failRemovals(true)
        try store.add("committed despite cleanup failure")
        XCTAssertEqual(store.cleanupIssue, .cleanupFailed)
        XCTAssertEqual(fixture.store().entries, store.entries)
    }

    func testMissingImageIsRetainedAndUnsafeFileReferencesAreRejected() throws {
        let fixture = try HistoryTestFixture()
        let store = fixture.store()
        let image = try ClipboardImageProcessor.prepare(HistoryTestFixture.image(), format: .png)
        try store.add(image)
        try store.add("still available")
        let path = store.imagesURL.appendingPathComponent(image.metadata.filename)
        try FileManager.default.removeItem(at: path)
        let restarted = fixture.store()
        XCTAssertFalse(restarted.isReadOnly)
        XCTAssertEqual(restarted.entries, store.entries)
        XCTAssertThrowsError(try restarted.readImage(image.metadata))
        let outside = fixture.root.appendingPathComponent("outside.png")
        try image.original.write(to: outside)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: outside)
        XCTAssertThrowsError(try restarted.readImage(image.metadata))
        try restarted.clear()
        XCTAssertEqual(restarted.cleanupIssue, .cleanupFailed)
        XCTAssertEqual(try Data(contentsOf: outside), image.original)
        let unsafe = ClipboardImage(format: .png, digest: "../../outside", width: 1, height: 1, byteCount: 1)
        let manifest = ClipboardHistoryStore.Manifest(entries: [.init(content: .image(unsafe))])
        let corrupt = try JSONEncoder().encode(manifest)
        try corrupt.write(to: store.indexURL)
        let rejected = fixture.store()
        XCTAssertTrue(rejected.isReadOnly)
        XCTAssertThrowsError(try rejected.clear())
        XCTAssertEqual(try Data(contentsOf: store.indexURL), corrupt)
    }

    @MainActor
    func testReaderPrioritizesOneImageAndIgnoresFinderPaths() throws {
        let fixture = try HistoryTestFixture()
        let png = try HistoryTestFixture.image()
        let tiff = try HistoryTestFixture.image(.tiff)
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        item.setString("附带文字", forType: .string)
        fixture.pasteboard.writeObjects([item])
        guard case .images(let candidates, _) = ClipboardCaptureReader.read(fixture.pasteboard) else {
            return XCTFail("Expected one image capture")
        }
        XCTAssertEqual(candidates.map(\.format), [.png, .tiff])
        XCTAssertEqual(candidates.first?.data, png)
        fixture.pasteboard.clearContents()
        let file = NSPasteboardItem()
        let fileURL = fixture.root.appendingPathComponent("fixture.png")
        try png.write(to: fileURL)
        file.setString(fileURL.absoluteString, forType: .fileURL)
        file.setString(fileURL.path, forType: .string)
        file.setData(png, forType: .png) // Finder preview is still a file-copy operation.
        fixture.pasteboard.writeObjects([file])
        XCTAssertNil(ClipboardCaptureReader.read(fixture.pasteboard))
        fixture.pasteboard.clearContents()
        let first = NSPasteboardItem()
        first.setData(png, forType: .png)
        let second = NSPasteboardItem()
        second.setData(png, forType: .png)
        fixture.pasteboard.writeObjects([first, second])
        guard case .rejected(.multipleItems) = ClipboardCaptureReader.read(fixture.pasteboard) else {
            return XCTFail("Multiple images must be skipped")
        }
    }

    @MainActor
    func testInvalidPNGFallsBackToValidTIFF() async throws {
        let fixture = try HistoryTestFixture()
        let controller = HistoryController(store: fixture.store())
        await controller.waitUntilIdle()
        let tiff = try HistoryTestFixture.image(.tiff)
        controller.capture(.images([.init(format: .png, data: Data()), .init(format: .tiff, data: tiff)], rejectedIssue: nil))
        await controller.waitUntilIdle()
        XCTAssertEqual(controller.entries.first?.image?.format, .tiff)
    }

    @MainActor
    func testGIFAndOversizedPNGDoNotBecomeAttachedText() throws {
        let fixture = try HistoryTestFixture()
        for (type, data, expected) in [
            (NSPasteboard.PasteboardType("com.compuserve.gif"), Data([0]), HistoryIssue.unsupportedImage),
            (.png, Data(count: 20_000_001), .imageTooLarge)
        ] {
            fixture.pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setData(data, forType: type)
            item.setString("do not capture this fallback text", forType: .string)
            fixture.pasteboard.writeObjects([item])
            guard case .rejected(let issue) = ClipboardCaptureReader.read(fixture.pasteboard) else {
                return XCTFail("Unsupported image must not become text")
            }
            XCTAssertEqual(issue, expected)
        }
    }
}
