import Foundation

// Run inside a real .app bundle to catch differences hidden by XCTest's bundle.
// Volatile arguments shadow history in this process only; never write user data.
let fixture = ["旧版记录一 📋", "旧版记录二\n保持原文"]
UserDefaults.standard.setVolatileDomain(
    ["clipboardHistory": fixture, "clipboardHistoryFormatVersion": 2],
    forName: UserDefaults.argumentDomain
)
precondition(Bundle.main.bundleIdentifier == "local.luokun.ClipTen")
precondition(CommandLine.arguments.count == 2)
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let manifest = ClipboardHistoryStore.Manifest(entries: fixture.map { ClipboardEntry(content: .text($0)) })
try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("history-v2.json"))
let store = ClipboardHistoryStore(directory: directory)
precondition(!store.isReadOnly)
precondition(store.entries.compactMap(\.text) == fixture)
print("Packaged default history initialization passed")
