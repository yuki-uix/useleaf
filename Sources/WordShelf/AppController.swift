import AppKit
import SwiftUI
import WordShelfCore
import OSLog

private let appLog = Logger(subsystem: "com.yuki.wordshelf", category: "Application")

private final class LookupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

@MainActor
private struct LookupRootView: View {
    @ObservedObject var model: AppModel
    let translation: AppleTranslationService

    var body: some View {
        LookupView(model: model)
            .wordShelfTranslationHost(translation, isActive: model.lookupHostVisible)
    }
}

@MainActor
private struct NotebookRootView: View {
    @ObservedObject var model: AppModel
    let translation: AppleTranslationService

    var body: some View {
        NotebookView(model: model)
            .wordShelfTranslationHost(translation, isActive: model.notebookHostVisible, allowsPreparation: true)
    }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model: AppModel
    private let translationService: AppleTranslationService
    private let selectionReader = SelectionReader()
    private let hotKey = GlobalHotKey()
    private var notebook: NSWindow?
    private var popup: LookupPanel?
    private var statusItem: NSStatusItem?
    private var sourceApplication: NSRunningApplication?
    private var captureTask: Task<Void, Never>?
    private var captureID = UUID()
    private var permissionTimer: Timer?

    override init() {
        let translation = AppleTranslationService()
        translationService = translation
        // Keep each app identity's data separate. The shipping identifier keeps
        // the existing directory; an independently identified QA build can use
        // disposable fixtures without touching the user's collection/profile.
        let identifier = Bundle.main.bundleIdentifier ?? "com.yuki.wordshelf"
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        model = AppModel(store: WordStore(directoryURL: directory), translator: translation)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onShowNotebook = { [weak self] in self?.showNotebook() }
        model.onDismissPopup = { [weak self] in self?.dismissPopup() }
        model.onShowManualLookup = { [weak self] in self?.showManualLookup() }
        model.onShowCurrentLookup = { [weak self] in self?.presentPopup() }
        model.onRequestAccessibility = { [weak self] in self?.requestAccessibility() }
        buildMenus()
        buildStatusItem()
        model.permissionGranted = selectionReader.isTrusted
        do {
            try hotKey.register { [weak self] in self?.captureSelection() }
        } catch {
            model.shortcutMessage = error.localizedDescription
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let granted = self.selectionReader.isTrusted
                if self.model.permissionGranted != granted { self.model.permissionGranted = granted }
            }
        }
        showNotebook()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.permissionGranted = selectionReader.isTrusted
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appLog.notice("application.reopen")
        showNotebook()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopPronunciation()
        permissionTimer?.invalidate()
        captureTask?.cancel()
        hotKey.unregister()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === popup {
            dismissPopup()
            return false
        }
        if sender === notebook {
            model.notebookHostVisible = false
            model.stopNotebookPronunciation()
            model.learning.endReview()
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === notebook {
            model.stopNotebookPronunciation()
            return
        }
        guard let panel = notification.object as? LookupPanel else { return }
        appLog.notice("popup.resignedKey")
        model.lookupHostVisible = false
        model.cancelLookup()
        panel.orderOut(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if notification.object is LookupPanel { appLog.notice("popup.becameKey") }
    }

    private func captureSelection() {
        appLog.notice("capture.start")
        if popup?.isKeyWindow == true {
            dismissPopup()
            return
        }
        guard captureTask == nil else { appLog.notice("capture.skipBusy"); return }
        let source = NSWorkspace.shared.frontmostApplication
        let id = UUID()
        captureID = id
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.captureID == id { self.captureTask = nil } }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source?.processIdentifier else {
                appLog.notice("capture.cancelledBeforeRead"); return
            }
            do {
                let selected = try await self.selectionReader.readSelection()
                appLog.notice("capture.readSucceeded")
                guard !Task.isCancelled else { return }
                self.model.captureMessage = nil
                self.model.lookup(selected)
            } catch {
                appLog.notice("capture.readFailed")
                guard !Task.isCancelled else { return }
                self.model.prepareManualLookup()
                self.model.captureMessage = error.localizedDescription
            }
            guard self.captureID == id,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == source?.processIdentifier else {
                appLog.notice("capture.cancelledBeforePresent"); return
            }
            self.model.permissionGranted = self.selectionReader.isTrusted
            self.sourceApplication = source?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : source
            self.presentPopup()
        }
    }

    @objc private func showManualLookup() {
        captureTask?.cancel()
        captureTask = nil
        captureID = UUID()
        sourceApplication = nil
        model.prepareManualLookup()
        presentPopup()
    }

    private func presentPopup() {
        appLog.notice("popup.present")
        if popup == nil {
            let panel = LookupPanel(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "拾用 · 查词"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            panel.animationBehavior = .utilityWindow
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: LookupRootView(model: model, translation: translationService))
            popup = panel
        }
        guard let panel = popup else { return }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            let x = min(max(pointer.x + 18, area.minX + 16), area.maxX - panel.frame.width - 16)
            let y = min(max(pointer.y - panel.frame.height - 18, area.minY + 16), area.maxY - panel.frame.height - 16)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        model.lookupHostVisible = true
        panel.makeKeyAndOrderFront(nil)
    }

    private func dismissPopup() {
        model.lookupHostVisible = false
        model.cancelLookup()
        popup?.orderOut(nil)
        if let sourceApplication, !sourceApplication.isTerminated {
            sourceApplication.activate(options: [])
        }
        sourceApplication = nil
    }

    @objc private func showNotebook() {
        captureTask?.cancel()
        captureTask = nil
        captureID = UUID()
        sourceApplication = nil
        model.lookupHostVisible = false
        model.cancelLookup()
        popup?.orderOut(nil)
        if notebook == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "拾用 · 生词本"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 680, height: 500)
            window.delegate = self
            window.contentView = NSHostingView(rootView: NotebookRootView(model: model, translation: translationService))
            window.center()
            notebook = window
        }
        model.notebookHostVisible = true
        NSApp.activate(ignoringOtherApps: true)
        notebook?.makeKeyAndOrderFront(nil)
    }

    @objc private func requestAccessibility() {
        selectionReader.requestAccess()
        model.permissionGranted = selectionReader.isTrusted
        if !model.permissionGranted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func exportWords() { model.exportWords() }
    @objc private func undoRemoval() { model.undoRemoval() }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func buildMenus() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于拾用", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("开启划词权限…", action: #selector(requestAccessibility)))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏拾用", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "退出拾用", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(item("查词…", action: #selector(showManualLookup), key: "l"))
        fileMenu.addItem(item("打开生词本", action: #selector(showNotebook), key: "b"))
        fileMenu.addItem(item("导出原文…", action: #selector(exportWords), key: "e"))
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(.separator())
        let undo = item("撤销移除单词", action: #selector(undoRemoval), key: "z")
        undo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(undo)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        menu.addItem(editItem)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }

    private func buildStatusItem() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "拾用")
        status.button?.toolTip = "拾用 · 划词后按 \(GlobalHotKey.displayString)"
        let menu = NSMenu()
        let hint = NSMenuItem(title: "划词查词  \(GlobalHotKey.displayString)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(item("手动查词…", action: #selector(showManualLookup)))
        menu.addItem(item("打开生词本", action: #selector(showNotebook)))
        menu.addItem(item("开启划词权限…", action: #selector(requestAccessibility)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出拾用", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        status.menu = menu
        statusItem = status
    }
}
