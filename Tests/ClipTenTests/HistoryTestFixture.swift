import AppKit
import ImageIO
import XCTest
@testable import ClipTen

final class HistoryTestFixture {
    let suiteName = "ClipTenTests.\(UUID().uuidString)"
    let root: URL
    let defaults: UserDefaults
    let pasteboard: NSPasteboard

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipTenTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suiteName)!
        pasteboard = NSPasteboard(name: .init(suiteName))
    }

    var directory: URL { root.appendingPathComponent("data") }
    func store(disk: any HistoryDisk = LocalHistoryDisk()) -> ClipboardHistoryStore {
        ClipboardHistoryStore(defaults: defaults, directory: directory, disk: disk)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: root)
    }

    static func image(_ format: ClipboardImageFormat = .png, width: Int = 32, height: Int = 16,
                      red: CGFloat = 0.5, frames: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.2, blue: 0.8, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, format.pasteboardType as CFString, frames, nil))
        for _ in 0..<frames { CGImageDestinationAddImage(destination, image, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

// Controlled fault injection; state can be safely toggled while the worker is running.
final class FaultHistoryDisk: HistoryDisk, @unchecked Sendable {
    private let lock = NSLock()
    private var writeFailure: String?
    private var readFailure: String?
    private var removeFailure = false
    private var imageReadGate: DispatchSemaphore?
    private var imageReadStarted: DispatchSemaphore?
    private var imageReads = 0
    var imageReadCount: Int { lock.withLock { imageReads } }
    private let real = LocalHistoryDisk()
    func failWrites(to name: String?) { lock.withLock { writeFailure = name } }
    func failReads(from name: String?) { lock.withLock { readFailure = name } }
    func failRemovals(_ value: Bool) { lock.withLock { removeFailure = value } }
    func blockNextImageRead(started: DispatchSemaphore, resume: DispatchSemaphore) {
        lock.withLock { imageReadStarted = started; imageReadGate = resume }
    }
    func exists(_ url: URL) -> Bool { real.exists(url) }
    func isSymbolicLink(_ url: URL) -> Bool { real.isSymbolicLink(url) }
    func isRegularFile(_ url: URL) -> Bool { real.isRegularFile(url) }
    func createDirectory(_ url: URL) throws { try real.createDirectory(url) }
    func read(_ url: URL, maximumBytes: Int?) throws -> Data {
        let state = lock.withLock { () -> (Bool, DispatchSemaphore?, DispatchSemaphore?) in
            let image = ["png", "tiff"].contains(url.pathExtension)
            if image { imageReads += 1 }
            let state = (readFailure == url.lastPathComponent, image ? imageReadStarted : nil, image ? imageReadGate : nil)
            if image { imageReadStarted = nil; imageReadGate = nil }
            return state
        }
        state.1?.signal()
        if let gate = state.2 { _ = gate.wait(timeout: .now() + 5) }
        if state.0 { throw CocoaError(.fileReadNoPermission) }
        return try real.read(url, maximumBytes: maximumBytes)
    }
    func writeAtomically(_ data: Data, to url: URL) throws {
        if lock.withLock({ writeFailure == url.lastPathComponent }) { throw CocoaError(.fileWriteOutOfSpace) }
        try real.writeAtomically(data, to: url)
    }
    func children(_ url: URL) throws -> [URL] { try real.children(url) }
    func remove(_ url: URL) throws {
        if lock.withLock({ removeFailure }) { throw CocoaError(.fileWriteNoPermission) }
        try real.remove(url)
    }
}
