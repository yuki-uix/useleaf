import AppKit
import SwiftUI
import WordShelfCore
import OSLog

private let appLog = Logger(subsystem: "com.yuki.wordshelf", category: "Application")

private final class LookupPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
private struct LookupRootView: View {
    @ObservedObject var model: AppModel
    let translation: AppleTranslationService
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        LookupView(model: model, onSizeChange: onSizeChange)
            .wordShelfTranslationHost(translation, isActive: model.lookupHostVisible)
    }
}

@MainActor
private struct SavedExpressionsRootView: View {
    @ObservedObject var model: AppModel
    let translation: AppleTranslationService
    let onCopy: (String) -> Void
    let onClose: () -> Void
    let onMore: () -> Void
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        SavedExpressionsView(model: model, onCopy: onCopy, onClose: onClose,
                             onMore: onMore, onSizeChange: onSizeChange)
            .wordShelfTranslationHost(translation, isActive: true)
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
    private var finder: LookupPanel?
    private var statusItem: NSStatusItem?
    private var sourceApplication: NSRunningApplication?
    private var finderSourceApplication: NSRunningApplication?
    private var translationReturnApplication: NSRunningApplication?
    private var popupAnchor = NSPoint.zero
    private var outsideClickMonitor: Any?
    private var clickMonitorID = UUID()
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
        model.onShowNotebook = { [weak self] in
            guard let self else { return }
            let previous = self.sourceApplication
            self.showNotebook()
            self.translationReturnApplication = previous
        }
        model.onDismissPopup = { [weak self] in self?.dismissPopup() }
        model.onShowManualLookup = { [weak self] in self?.showManualLookup() }
        model.onShowCurrentLookup = { [weak self] in
            guard let self else { return }
            self.sourceApplication = self.translationReturnApplication
            self.translationReturnApplication = nil
            if let previous = self.sourceApplication, !previous.isTerminated {
                self.model.notebookHostVisible = false
                self.notebook?.orderOut(nil)
                NSApp.setActivationPolicy(.accessory)
                previous.activate(options: [])
            }
            self.presentPopup()
        }
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
        // A companion starts quietly in the menu bar. Reopening it from Apps
        // brings up the small finder, rather than a study dashboard.
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.permissionGranted = selectionReader.isTrusted
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appLog.notice("application.reopen")
        showFinder()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopPronunciation()
        permissionTimer?.invalidate()
        captureTask?.cancel()
        hotKey.unregister()
        removeOutsideClickMonitor()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === popup {
            dismissPopup()
            return false
        }
        if sender === finder {
            dismissFinder()
            return false
        }
        if sender === notebook {
            model.notebookHostVisible = false
            model.stopNotebookPronunciation()
            model.learning.endReview()
            NSApp.setActivationPolicy(.accessory)
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === notebook {
            model.stopNotebookPronunciation()
            return
        }
        if let panel = notification.object as? NSWindow, panel === popup,
           model.lookupHostVisible {
            appLog.notice("popup.resignedKey")
            dismissPopup(restoreSource: false)
        } else if let panel = notification.object as? NSWindow, panel === finder,
                  finder?.isVisible == true {
            dismissFinder(restoreSource: false)
        }
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
        dismissFinder(restoreSource: false)
        translationReturnApplication = nil
        let source = NSWorkspace.shared.frontmostApplication
        popupAnchor = NSEvent.mouseLocation
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
        let previous = finderSourceApplication ?? externalFrontmostApplication()
        dismissFinder(restoreSource: false)
        translationReturnApplication = nil
        sourceApplication = previous
        popupAnchor = NSEvent.mouseLocation
        model.prepareManualLookup()
        presentPopup()
    }

    private func presentPopup() {
        appLog.notice("popup.present")
        if popup == nil {
            let panel = makeCompanionPanel(size: NSSize(width: 360, height: 220))
            panel.title = "拾用 · 查词"
            panel.onCancel = { [weak self] in self?.dismissPopup() }
            popup = panel
            let host = NSHostingView(rootView: LookupRootView(model: model, translation: translationService,
                onSizeChange: { [weak self] size in self?.resizePopup(to: size) }))
            prepareHostingView(host)
            panel.contentView = host
        }
        guard let panel = popup else { return }
        placePopup()
        model.lookupHostVisible = true
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
    }

    private func dismissPopup(restoreSource: Bool = true) {
        let previous = sourceApplication
        sourceApplication = nil
        model.lookupHostVisible = false
        model.cancelLookup()
        popup?.orderOut(nil)
        if restoreSource, let previous, !previous.isTerminated {
            previous.activate(options: [])
        }
        removeOutsideClickMonitorIfIdle()
    }

    private func externalFrontmostApplication() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app
    }

    private func makeCompanionPanel(size: NSSize) -> LookupPanel {
        let panel = LookupPanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        return panel
    }

    private func prepareHostingView(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
    }

    private func resizePopup(to size: CGSize) {
        guard let panel = popup, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }
        let area = (NSScreen.screens.first { $0.frame.contains(popupAnchor) } ?? NSScreen.main)?.visibleFrame
        let fitted = NSSize(width: min(ceil(size.width), (area?.width ?? 1000) - 32),
                            height: min(ceil(size.height), (area?.height ?? 800) - 32))
        if panel.frame.size != fitted { panel.setContentSize(fitted) }
        placePopup()
    }

    private func placePopup() {
        guard let panel = popup,
              let area = (NSScreen.screens.first { $0.frame.contains(popupAnchor) } ?? NSScreen.main)?.visibleFrame else { return }
        let x = min(max(popupAnchor.x + 12, area.minX + 16), area.maxX - panel.frame.width - 16)
        let below = popupAnchor.y - panel.frame.height - 14
        let desiredY = below >= area.minY + 16 ? below : popupAnchor.y + 14
        let y = min(max(desiredY, area.minY + 16), area.maxY - panel.frame.height - 16)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func showFinder() {
        captureTask?.cancel()
        captureTask = nil
        captureID = UUID()
        let previous = sourceApplication ?? externalFrontmostApplication()
        dismissPopup(restoreSource: false)
        dismissFinder(restoreSource: false)
        model.notice = nil
        finderSourceApplication = previous
        let panel = makeCompanionPanel(size: NSSize(width: 360, height: 230))
        panel.title = "拾用 · 找回收藏"
        panel.onCancel = { [weak self] in self?.dismissFinder() }
        finder = panel
        // Recreate the root each time. Removing it on close cancels its SwiftUI
        // task and unregisters its translation host, even though the app stays.
        let host = NSHostingView(rootView: SavedExpressionsRootView(
            model: model, translation: translationService,
            onCopy: { [weak self] word in
                guard let self, self.model.copySavedOriginal(word) else { return }
                self.dismissFinder()
            },
            onClose: { [weak self] in self?.dismissFinder() },
            onMore: { [weak self] in self?.showNotebook() },
            onSizeChange: { [weak self] size in self?.resizeFinder(to: size) }
        ))
        prepareHostingView(host)
        panel.contentView = host
        placeFinder()
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
    }

    private func resizeFinder(to size: CGSize) {
        guard let panel = finder, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }
        let area = statusItem?.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let fitted = NSSize(width: min(ceil(size.width), (area?.width ?? 1000) - 24),
                            height: min(ceil(size.height), (area?.height ?? 800) - 24))
        if panel.frame.size != fitted { panel.setContentSize(fitted) }
        placeFinder()
    }

    private func placeFinder() {
        guard let panel = finder else { return }
        let button = statusItem?.button
        let anchor = button.flatMap { b in b.window?.convertToScreen(b.convert(b.bounds, to: nil)) }
        let screen = button?.window?.screen ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let x = min(max((anchor?.maxX ?? area.midX) - panel.frame.width, area.minX + 12), area.maxX - panel.frame.width - 12)
        let y = min(max((anchor?.minY ?? area.maxY) - panel.frame.height - 6, area.minY + 12), area.maxY - panel.frame.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func dismissFinder(restoreSource: Bool = true) {
        let previous = finderSourceApplication
        finderSourceApplication = nil
        let panel = finder
        finder = nil
        model.stopNotebookPronunciation()
        panel?.orderOut(nil)
        panel?.contentView = nil
        if restoreSource, let previous, !previous.isTerminated { previous.activate(options: []) }
        removeOutsideClickMonitorIfIdle()
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        let id = UUID()
        clickMonitorID = id
        // Observe mouse-down only while a transient surface is visible. No
        // page content or keys are read, and no event history is retained.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.clickMonitorID == id else { return }
                self.dismissPopup(restoreSource: false)
                self.dismissFinder(restoreSource: false)
            }
        }
    }

    private func removeOutsideClickMonitorIfIdle() {
        if !model.lookupHostVisible && finder == nil { removeOutsideClickMonitor() }
    }

    private func removeOutsideClickMonitor() {
        clickMonitorID = UUID()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    @objc private func showNotebook() {
        captureTask?.cancel()
        captureTask = nil
        captureID = UUID()
        sourceApplication = nil
        dismissFinder(restoreSource: false)
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
        NSApp.setActivationPolicy(.regular)
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

    @objc private func exportWords() { showNotebook(); model.exportWords() }
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
        fileMenu.addItem(item("找回收藏", action: #selector(showFinder), key: "b"))
        fileMenu.addItem(item("管理收藏与选项…", action: #selector(showNotebook)))
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
        let image = NSImage(size: NSSize(width: 19, height: 19), flipped: true) { rectangle in
            guard let graphics = NSGraphicsContext.current?.cgContext else { return false }
            UseleafArtwork.draw(in: graphics, size: rectangle.size, includesTile: false)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "拾用 · 找回收藏"
        status.button?.image = image
        status.button?.toolTip = "拾用 · 找回收藏（划词查译 \(GlobalHotKey.displayString)）"
        status.button?.target = self
        status.button?.action = #selector(statusItemClicked(_:))
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = status
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            dismissFinder(restoreSource: false)
            dismissPopup(restoreSource: false)
            guard let button = statusItem?.button else { return }
            statusMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        } else if finder?.isVisible == true {
            dismissFinder()
        } else {
            showFinder()
        }
    }

    private func statusMenu() -> NSMenu {
        let menu = NSMenu()
        let hint = NSMenuItem(title: "划词查词  \(GlobalHotKey.displayString)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(item("手动查词…", action: #selector(showManualLookup)))
        menu.addItem(item("管理收藏与选项…", action: #selector(showNotebook)))
        menu.addItem(item("导出原文…", action: #selector(exportWords)))
        menu.addItem(item("开启划词权限…", action: #selector(requestAccessibility)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出拾用", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }
}
