import AppKit
@preconcurrency import ApplicationServices
import Carbon

/// Reads only the selection requested by the user's hot key. Context, page
/// contents, and URLs are deliberately not collected.
@MainActor
final class SelectionReader {
    var isTrusted: Bool { AXIsProcessTrusted() }
    private var isReading = false

    init() {}

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func readSelection() async throws -> String {
        guard !isReading else { throw SelectionError.alreadyReading }
        guard isTrusted else { throw SelectionError.permissionRequired }
        guard !IsSecureEventInputEnabled() else { throw SelectionError.secureInput }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw SelectionError.noSelection
        }
        isReading = true
        defer { isReading = false }

        let processID = application.processIdentifier
        let focusedElement = focusedElement(in: processID)
        if let focusedElement {
            guard !isSecure(focusedElement) else { throw SelectionError.secureInput }
            if let selectedText = selectedText(from: focusedElement) {
                return selectedText
            }
        }

        return try await copySelection(from: processID)
    }

    private func focusedElement(in processID: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.25)
        return elementAttribute(application, kAXFocusedUIElementAttribute)
    }

    private func selectedText(from element: AXUIElement) -> String? {
        var candidate: AXUIElement? = element
        // Web content may expose a focused descendant but put its selection on
        // its containing text area. Inspect a bounded parent chain, not the page.
        for _ in 0..<5 {
            guard let current = candidate else { break }
            AXUIElementSetMessagingTimeout(current, 0.15)
            if let text = stringAttribute(current, kAXSelectedTextAttribute),
               let nonempty = nonemptyText(text) {
                return nonempty
            }
            candidate = elementAttribute(current, kAXParentAttribute)
        }
        return nil
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        stringAttribute(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole
            || stringAttribute(element, kAXRoleAttribute) == kAXSecureTextFieldSubrole
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copySelection(from processID: pid_t) async throws -> String {
        // Sending ⌘C while the user's Ctrl/Option key remains down changes the
        // command in some applications. Wait for release without blocking AppKit.
        let releaseDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !keyboardModifiersAreReleased {
            try Task.checkCancellation()
            guard isStillFrontmost(processID) else { throw SelectionError.applicationChanged }
            guard ContinuousClock.now < releaseDeadline else { throw SelectionError.releaseKeys }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard isStillFrontmost(processID) else { throw SelectionError.applicationChanged }
        guard !IsSecureEventInputEnabled() else { throw SelectionError.secureInput }
        if let focused = focusedElement(in: processID), isSecure(focused) {
            throw SelectionError.secureInput
        }

        try Task.checkCancellation()
        let pasteboard = NSPasteboard.general
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)
        let originalChangeCount = snapshot.changeCount

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            throw SelectionError.copyUnavailable
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        try Task.checkCancellation()
        guard pasteboard.changeCount == originalChangeCount else {
            throw SelectionError.clipboardChanged
        }
        guard isStillFrontmost(processID) else { throw SelectionError.applicationChanged }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return try await ClipboardCopyTransaction(pasteboard: pasteboard, snapshot: snapshot)
            .readCopiedText(isSourceFrontmost: { self.isStillFrontmost(processID) })
    }

    private var keyboardModifiersAreReleased: Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        return flags.intersection(modifiers).isEmpty
    }

    private func isStillFrontmost(_ processID: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
    }

    private func nonemptyText(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// The post-copy cleanup is independent of AX and event synthesis so its failure
/// paths can be tested using a named pasteboard without touching user state.
@MainActor
struct ClipboardCopyTransaction {
    let pasteboard: NSPasteboard
    let snapshot: PasteboardSnapshot

    func readCopiedText(
        isSourceFrontmost: () -> Bool,
        timeoutMilliseconds: Int = 700,
        pause: (Int) async -> Void = ClipboardCopyTransaction.pause
    ) async throws -> String {
        var capturedChangeCount: Int?
        var sourceChanged = false
        defer {
            if let capturedChangeCount {
                snapshot.restore(to: pasteboard, ifUnchangedSince: capturedChangeCount)
            }
        }

        let copyDeadline = ContinuousClock.now.advanced(by: .milliseconds(timeoutMilliseconds))
        while true {
            // Inspect the clipboard before checking the foreground process. The
            // posted copy may already have completed when focus changes, and
            // that write still needs restoring even though lookup is aborted.
            let changedCount = pasteboard.changeCount
            let copyArrived = changedCount != snapshot.changeCount
            if copyArrived { capturedChangeCount = changedCount }
            if !isSourceFrontmost() { sourceChanged = true }

            if copyArrived {
                // Wait for promised representations to settle. If a later copy
                // replaces this version, preserve that newer clipboard value.
                await pause(45)
                guard pasteboard.changeCount == changedCount else {
                    capturedChangeCount = nil
                    throw SelectionError.clipboardChanged
                }
                if !isSourceFrontmost() { sourceChanged = true }
                try Task.checkCancellation()
                guard !sourceChanged else { throw SelectionError.applicationChanged }
                guard let copiedText = pasteboard.string(forType: .string) else {
                    throw SelectionError.noSelection
                }
                let text = copiedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw SelectionError.noSelection }
                guard pasteboard.changeCount == changedCount else {
                    capturedChangeCount = nil
                    throw SelectionError.clipboardChanged
                }
                return text
            }

            if ContinuousClock.now >= copyDeadline { break }
            // Once copy has been posted, cancellation or a focus change stops
            // reading its result but does not skip the bounded cleanup wait.
            // A nonthrowing delay lets the pending write arrive and be restored.
            await pause(20)
        }
        try Task.checkCancellation()
        if sourceChanged { throw SelectionError.applicationChanged }
        throw SelectionError.noSelection
    }

    static func pause(milliseconds: Int) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                continuation.resume()
            }
        }
    }
}

@MainActor
struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
    let changeCount: Int

    init(pasteboard: NSPasteboard) throws {
        let initialChangeCount = pasteboard.changeCount
        var snapshot: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                // If a promised representation cannot be materialized, leave
                // the clipboard intact and let the user enter the word instead.
                guard let data = item.data(forType: type) else {
                    throw SelectionError.clipboardUnavailable
                }
                representations[type] = data
            }
            snapshot.append(representations)
        }
        guard pasteboard.changeCount == initialChangeCount else {
            throw SelectionError.clipboardChanged
        }
        self.items = snapshot
        self.changeCount = initialChangeCount
    }

    /// Returning false leaves a newer clipboard version completely untouched.
    @discardableResult
    func restore(to pasteboard: NSPasteboard, ifUnchangedSince expectedChangeCount: Int) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else { return false }
        let restoredItems = items.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        pasteboard.clearContents()
        if !restoredItems.isEmpty { pasteboard.writeObjects(restoredItems) }
        return true
    }
}

enum SelectionError: LocalizedError, Equatable {
    case permissionRequired, noSelection, secureInput, applicationChanged
    case copyUnavailable, clipboardUnavailable, clipboardChanged, releaseKeys, alreadyReading

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "开启辅助功能权限后，即可读取选中的单词、短语和句子。现在也可以直接输入原文。"
        case .noSelection:
            return "没有读取到选中的文字。请先选中英文单词、短语或句子，再按 ⌃⌥D；也可以在这里直接输入。"
        case .secureInput:
            return "当前应用正在使用安全输入，暂时无法读取选文。可以在这里直接输入原文。"
        case .applicationChanged:
            return "读取时切换了应用，请回到原文重新划词，或在这里直接输入。"
        case .copyUnavailable:
            return "暂时无法读取当前选词，可以在这里直接输入。"
        case .clipboardUnavailable:
            return "当前剪贴板内容无法完整保留，请直接输入单词查词。"
        case .clipboardChanged:
            return "读取时剪贴板发生了变化，请重新划词查词。"
        case .releaseKeys:
            return "按下 ⌃⌥D 后，请松开快捷键以读取选词。"
        case .alreadyReading:
            return "正在读取选词，请稍候。"
        }
    }
}
