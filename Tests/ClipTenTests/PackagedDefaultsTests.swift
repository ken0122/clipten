import Foundation
import XCTest

final class PackagedDefaultsTests: XCTestCase {
    func testDefaultStoreInitializesInsideReleasedBundleIdentity() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipTenBundleTests-\(UUID().uuidString)")
        let contents = temporary.appendingPathComponent("Probe.app/Contents")
        let executable = contents.appendingPathComponent("MacOS/Probe")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        let plist: [String: Any] = [
            "CFBundleIdentifier": "local.luokun.ClipTen",
            "CFBundleExecutable": "Probe",
            "CFBundlePackageType": "APPL"
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))

        try run("/usr/bin/xcrun", arguments: [
            "swiftc", "-O",
            root.appendingPathComponent("Sources/ClipTen/ClipboardHistoryStore.swift").path,
            root.appendingPathComponent("Tests/Fixtures/PackagedDefaultsProbe/main.swift").path,
            "-o", executable.path
        ])
        try run(executable.path, arguments: [])
    }

    private func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 0, "Failed: \(executable)")
    }
}
