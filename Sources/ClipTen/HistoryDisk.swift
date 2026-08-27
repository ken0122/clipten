import Foundation

// Injection boundary for deterministic disk-full, interrupted-write and cleanup tests.
protocol HistoryDisk: Sendable {
    func exists(_ url: URL) -> Bool
    func isSymbolicLink(_ url: URL) -> Bool
    func isRegularFile(_ url: URL) -> Bool
    func createDirectory(_ url: URL) throws
    func read(_ url: URL, maximumBytes: Int?) throws -> Data
    func writeAtomically(_ data: Data, to url: URL) throws
    func children(_ url: URL) throws -> [URL]
    func remove(_ url: URL) throws
}

struct LocalHistoryDisk: HistoryDisk {
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeSymbolicLink
    }
    func isRegularFile(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeRegular
    }
    func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }
    func read(_ url: URL, maximumBytes: Int?) throws -> Data {
        if let maximumBytes {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= maximumBytes else {
                throw HistoryIssue.imageTooLarge
            }
        }
        let data = try Data(contentsOf: url)
        if let maximumBytes, data.count > maximumBytes { throw HistoryIssue.imageTooLarge }
        return data
    }
    func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        // Failure after replacement must not masquerade as an uncommitted write.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func children(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
    func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
}
