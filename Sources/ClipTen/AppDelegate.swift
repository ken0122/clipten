/*
 THESIS: Ten recent clipboard texts and images live in one native menu, without a dashboard or floating window.
 OWN-WORLD: Native macOS menu materials, system typography, one template clipboard symbol, and familiar separators and commands.
 STORY: Copy normally, open the menu when something is needed again, then choose the remembered text to copy it back.
 FIRST VIEWPORT: A compact native menu headed “最近复制”, followed immediately by up to ten readable previews and two utility commands.
 FORM: Operate-mode system menu; the precisely specified native-only workflow is exempt from concept-roll staging and has no seed key.
 */

import AppKit
import ClipTenDesign

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let history: HistoryController
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
        historyStore: ClipboardHistoryStore? = nil,
        pasteboard: NSPasteboard = .general,
        historyMenuPresenter: (@MainActor (NSMenu) -> Void)? = nil
    ) {
        self.history = HistoryController(store: historyStore)
        self.pasteboard = pasteboard
        self.historyMenuPresenter = historyMenuPresenter
        super.init()
        menu.autoenablesItems = false
        history.onChange = { [weak self] in self?.updateStatusFeedback() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        registeredGlobalShortcutSlots = globalShortcutManager.register()

        history.whenReady { [weak self] in
            guard let self else { return }
            self.prepareClipboardMonitoring()
            self.clipboardTimer = Timer.scheduledTimer(
                timeInterval: 0.6, target: self, selector: #selector(self.checkClipboard),
                userInfo: nil, repeats: true
            )
            self.clipboardTimer?.tolerance = 0.15
            self.requestHistoryMenu()
        }
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

    func rebuildMenu() {
        menu.removeAllItems()

        let heading = NSMenuItem(title: "最近复制", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())

        if history.entries.isEmpty {
            let title = history.isLoading ? "正在恢复历史…"
                : (history.isReadOnly ? "历史暂不可用，请检查存储" : "还没有剪贴板记录")
            let emptyItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, entry) in history.entries.enumerated() {
                let title: String
                switch entry.content {
                case .text(let text): title = preview(for: text)
                case .image(let image):
                    title = "图片 · \(image.width)×\(image.height)" + (history.unavailable.contains(entry.id) ? "（不可用）" : "")
                }
                let item = NSMenuItem(
                    title: title,
                    action: #selector(copyHistoryItem(_:)),
                    keyEquivalent: registeredGlobalShortcutSlots.contains(index)
                        ? (index < 9 ? String(index + 1) : "0")
                        : ""
                )
                item.keyEquivalentModifierMask = [.control, .shift]
                item.target = self
                item.representedObject = entry.id
                item.isEnabled = !history.isClearing && !history.unavailable.contains(entry.id)
                item.toolTip = entry.text ?? title
                item.image = history.thumbnails[entry.id]
                item.setAccessibilityLabel("复制：\(entry.text.map { preview(for: $0, limit: 140) } ?? title)")
                menu.addItem(item)
            }

            let unavailableSlots = Set(0..<min(history.entries.count, 10))
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

        if let issue = history.issue {
            let warning = NSMenuItem(title: issue.localizedDescription, action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(.separator())
        } else if !history.unavailable.isEmpty {
            let warning = NSMenuItem(title: "部分图片不可用，其他记录仍保留", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let clearItem = NSMenuItem(
            title: "清空记录",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.isEnabled = !history.entries.isEmpty && !history.isLoading && !history.isReadOnly && !history.isClearing
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
        // Startup only restores history, even when empty: recapturing here would
        // resurrect the last clipboard value after the user clears and restarts.
    }

    @objc func checkClipboard() {
        guard history.canCapture else { return }
        guard pasteboard.changeCount != lastPasteboardChangeCount else { return }
        captureCurrentClipboard()
    }

    private func captureCurrentClipboard() {
        guard history.canCapture else { return }
        let changeCount = pasteboard.changeCount
        let capture = ClipboardCaptureReader.read(pasteboard)
        // The pasteboard may change while fetching representations from another app.
        guard changeCount == pasteboard.changeCount else { return }
        lastPasteboardChangeCount = changeCount
        if let capture { history.capture(capture) }
    }

    @objc func copyHistoryItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        copy(id)
    }

    func copyHistoryEntry(at slot: Int) {
        guard history.entries.indices.contains(slot) else { return }
        copy(history.entries[slot].id)
    }

    private func copy(_ id: UUID) {
        history.copy(id: id, to: pasteboard, didWrite: { [weak self] count in
            self?.lastPasteboardChangeCount = count
        }) { [weak self] success in
            if success { self?.showCopiedFeedback() }
        }
    }

    @objc func clearHistory() {
        lastPasteboardChangeCount = pasteboard.changeCount
        history.clear()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func showCopiedFeedback() {
        feedbackWorkItem?.cancel()
        statusItem?.button?.image = statusImage(named: "checkmark")

        let workItem = DispatchWorkItem { [weak self] in
            self?.updateStatusFeedback()
        }
        feedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func updateStatusFeedback() {
        let message = history.issue?.localizedDescription
            ?? (history.unavailable.isEmpty ? nil : "部分图片不可用，其他记录仍保留")
        statusItem?.button?.image = message == nil ? ClipTenIcon.statusImage() : statusImage(named: "exclamationmark.triangle")
        statusItem?.button?.toolTip = message ?? "ClipTen · 最近 10 条文字与图片"
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
