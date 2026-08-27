/*
 THESIS: Ten recent clipboard texts live where the task begins: the menu bar, never in a dashboard or floating window.
 OWN-WORLD: Native macOS menu materials, system typography, one template clipboard symbol, and familiar separators and commands.
 STORY: Copy normally, open the menu when something is needed again, then choose the remembered text to copy it back.
 FIRST VIEWPORT: A compact native menu headed “最近复制”, followed immediately by up to ten readable previews and two utility commands.
 FORM: Operate-mode system menu; the precisely specified native-only workflow is exempt from concept-roll staging and has no seed key.
 */

import AppKit
import ClipTenDesign

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let historyStore: ClipboardHistoryStore
    private let pasteboard: NSPasteboard
    private let menu = NSMenu()

    private var statusItem: NSStatusItem?
    private var clipboardTimer: Timer?
    private var lastPasteboardChangeCount = 0
    private var feedbackWorkItem: DispatchWorkItem?

    init(
        historyStore: ClipboardHistoryStore = ClipboardHistoryStore(),
        pasteboard: NSPasteboard = .general
    ) {
        self.historyStore = historyStore
        self.pasteboard = pasteboard
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        lastPasteboardChangeCount = pasteboard.changeCount
        captureCurrentClipboard()

        clipboardTimer = Timer.scheduledTimer(
            timeInterval: 0.6,
            target: self,
            selector: #selector(checkClipboard),
            userInfo: nil,
            repeats: true
        )
        clipboardTimer?.tolerance = 0.15
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardTimer?.invalidate()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = ClipTenIcon.statusImage()
        item.button?.toolTip = "ClipTen · 最近 10 条剪贴板"
        item.menu = menu

        menu.delegate = self
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let heading = NSMenuItem(title: "最近复制", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())

        if historyStore.entries.isEmpty {
            let emptyItem = NSMenuItem(title: "还没有剪贴板记录", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, text) in historyStore.entries.enumerated() {
                let item = NSMenuItem(
                    title: preview(for: text),
                    action: #selector(copyHistoryItem(_:)),
                    keyEquivalent: index < 9 ? String(index + 1) : "0"
                )
                item.keyEquivalentModifierMask = [.command]
                item.target = self
                item.representedObject = text
                item.toolTip = text
                item.setAccessibilityLabel("复制：\(preview(for: text, limit: 140))")
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let clearItem = NSMenuItem(
            title: "清空记录",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.isEnabled = !historyStore.entries.isEmpty
        menu.addItem(clearItem)

        let quitItem = NSMenuItem(
            title: "退出 ClipTen",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func checkClipboard() {
        guard pasteboard.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pasteboard.changeCount
        captureCurrentClipboard()
    }

    private func captureCurrentClipboard() {
        guard let text = pasteboard.string(forType: .string) else { return }
        _ = historyStore.add(text)
    }

    @objc func copyHistoryItem(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastPasteboardChangeCount = pasteboard.changeCount
        _ = historyStore.add(text)
        showCopiedFeedback()
    }

    @objc private func clearHistory() {
        historyStore.clear()
        rebuildMenu()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func showCopiedFeedback() {
        feedbackWorkItem?.cancel()
        statusItem?.button?.image = statusImage(named: "checkmark")

        let workItem = DispatchWorkItem { [weak self] in
            self?.statusItem?.button?.image = ClipTenIcon.statusImage()
        }
        feedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func statusImage(named symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ClipTen")
        image?.isTemplate = true
        return image
    }

    private func preview(for text: String, limit: Int = 72) -> String {
        let singleLine = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit - 1)) + "…"
    }
}
