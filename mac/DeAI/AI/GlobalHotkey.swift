import Carbon
import Foundation

/// The "rewrite the current scope" global shortcut. Persisted in
/// AppSettings; `off` means unregistered.
enum RewriteHotkey: String, Codable, CaseIterable {
    case ctrlOptR
    case ctrlOptE
    case optCmdJ
    case off

    var label: String {
        switch self {
        case .ctrlOptR: return "⌃⌥ R"
        case .ctrlOptE: return "⌃⌥ E"
        case .optCmdJ: return "⌥⌘ J"
        case .off: return "关闭"
        }
    }

    /// Carbon RegisterEventHotKey arguments.
    var spec: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .ctrlOptR:
            return (UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey))
        case .ctrlOptE:
            return (UInt32(kVK_ANSI_E), UInt32(controlKey | optionKey))
        case .optCmdJ:
            return (UInt32(kVK_ANSI_J), UInt32(optionKey | cmdKey))
        case .off:
            return nil
        }
    }
}

/// Thin wrapper over Carbon RegisterEventHotKey — works regardless of which
/// app is frontmost (the rewrite panel never activates, same as the card).
final class GlobalHotkey {
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func set(_ spec: (keyCode: UInt32, modifiers: UInt32)?) {
        unregister()
        guard let spec else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: 0x4445_4149, id: 1) // 'DEAI'
        RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let me = Unmanaged<GlobalHotkey>
                    .fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { me.onPress?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    deinit {
        unregister()
        if let h = handlerRef { RemoveEventHandler(h) }
    }
}
