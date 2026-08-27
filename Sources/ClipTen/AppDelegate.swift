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
    private let historyMenuPresenter: (@MainActor (NSMenu) -> Void)?
    private var isHistoryMenuPresentationPending = false

    private var statusItem: NSStatusItem?
    private var clipboardTimer: Timer?
    private var lastPasteboardChangeCount = 0
    private var feedbackWorkItem: DispatchWorkItem?
    private var registeredGlobalShortcutSlots: Set<Int> = []

    private lazy var globalShortcutManager = GlobalShortcutManager { [weak self] slot in
        self?.copyHistoryEntry(at: slot)
    }

    init(
        historyStore: ClipboardHistoryStore = ClipboardHistoryStore(),
        pasteboard: NSPasteboard = .general,
        historyMenuPresenter: (@MainActor (NSMenu) -> Void)? = nil
    ) {
        self.historyStore = historyStore
        self.pasteboard = pasteboard
        self.historyMenuPresenter = historyMenuPresenter
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        registeredGlobalShortcutSlots = globalShortcutManager.register()

        prepareClipboardMonitoring()

        clipboardTimer = Timer.scheduledTimer(
            timeInterval: 0.6,
            target: self,
            selector: #selector(checkClipboard),
            userInfo: nil,
            repeats: true
        )
        clipboardTimer?.tolerance = 0.15
        requestHistoryMenu()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        requestHistoryMenu()
        return false
    }

    func requestHistoryMenu() {
        // Coalesce launch/reopen events and avoid nesting menu tracking loops.
        guard !isHistoryMenuPresentationPending else { return }
        isHistoryMenuPresentationPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.isHistoryMenuPresentationPending = false }
            self.rebuildMenu()
            if let presenter = self.historyMenuPresenter {
                presenter(self.menu)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                // A screen-space popup works even when the status item is hidden
                // behind the notch. AppKit keeps it within the screen bounds.
                self.menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardTimer?.invalidate()
        globalShortcutManager.unregister()
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
                    keyEquivalent: registeredGlobalShortcutSlots.contains(index)
                        ? (index < 9 ? String(index + 1) : "0")
                        : ""
                )
                item.keyEquivalentModifierMask = [.control, .shift]
                item.target = self
                item.representedObject = text
                item.toolTip = text
                item.setAccessibilityLabel("复制：\(preview(for: text, limit: 140))")
                menu.addItem(item)
            }

            let unavailableSlots = Set(0..<min(historyStore.entries.count, 10))
                .subtracting(registeredGlobalShortcutSlots)
                .sorted()
            if !unavailableSlots.isEmpty {
                menu.addItem(.separator())
                let unavailableKeys = unavailableSlots
                    .map { $0 == 9 ? "0" : String($0 + 1) }
                    .joined(separator: "、")
                let warning = NSMenuItem(
                    title: "快捷键不可用：\(unavailableKeys)",
                    action: nil,
                    keyEquivalent: ""
                )
                warning.isEnabled = false
                menu.addItem(warning)
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

    func prepareClipboardMonitoring() {
        lastPasteboardChangeCount = pasteboard.changeCount
        // Restarting/upgrading must not reorder or evict restored history.
        // Only a fresh history captures the clipboard immediately.
        if historyStore.entries.isEmpty {
            captureCurrentClipboard()
        }
    }

    @objc func checkClipboard() {
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
        copy(text)
    }

    func copyHistoryEntry(at slot: Int) {
        guard historyStore.entries.indices.contains(slot) else { return }
        copy(historyStore.entries[slot])
    }

    private func copy(_ text: String) {
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
