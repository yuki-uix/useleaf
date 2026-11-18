import AppKit
import Carbon
import OSLog

private let shortcutLog = Logger(subsystem: "com.yuki.wordshelf", category: "Shortcut")

/// Carbon hot keys work while another application is frontmost and do not need
/// a global keyboard monitor or Input Monitoring permission.
@MainActor
final class GlobalHotKey {
    static let displayString = "⌃⌥D"

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?
    private static let identifier = EventHotKeyID(signature: 0x57534846, id: 1) // WSHF

    init() {}

    isolated deinit {
        unregister()
    }

    func register(handler: @escaping @MainActor () -> Void) throws {
        unregister()
        action = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr,
                      identifier.signature == 0x57534846,
                      identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                shortcutLog.notice("shortcut.received")
                Task { @MainActor in owner.action?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else {
            unregister()
            throw HotKeyError.registrationFailed(installStatus)
        }

        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(controlKey | optionKey),
            Self.identifier,
            GetEventDispatcherTarget(),
            UInt32(kEventHotKeyExclusive),
            &hotKey
        )
        guard registrationStatus == noErr else {
            unregister()
            throw HotKeyError.registrationFailed(registrationStatus)
        }
        shortcutLog.notice("shortcut.registered")
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
        action = nil
    }
}

private enum HotKeyError: LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            if status == eventHotKeyExistsErr {
                return "快捷键 ⌃⌥D 已被其他应用使用。关闭占用后，重新打开拾用即可重试；现在仍可手动查词。"
            }
            return "暂时无法启用快捷键 ⌃⌥D（\(status)），仍可从菜单栏打开查词。"
        }
    }
}
