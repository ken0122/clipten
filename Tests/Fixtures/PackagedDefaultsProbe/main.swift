import Foundation

// Run inside a real .app bundle to catch differences hidden by XCTest's bundle.
// Volatile arguments shadow history in this process only; never write user data.
let fixture = ["旧版记录一 📋", "旧版记录二\n保持原文"]
UserDefaults.standard.setVolatileDomain(
    ["clipboardHistory": fixture],
    forName: UserDefaults.argumentDomain
)
precondition(Bundle.main.bundleIdentifier == "local.luokun.ClipTen")
precondition(ClipboardHistoryStore().entries == fixture)
print("Packaged default history initialization passed")
