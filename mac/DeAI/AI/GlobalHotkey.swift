import AppKit
import Carbon
import Foundation

/// The "rewrite the current scope" global shortcut, recorded by the user
/// (System Settings / Raycast style). Persisted in AppSettings;
/// `keyCode == nil` means unregistered (off). `modifiers` is a Carbon mask
/// (cmdKey/optionKey/controlKey/shiftKey).
struct RewriteHotkey: Codable, Equatable {
    var keyCode: UInt32?
    var modifiers: UInt32 = 0

    static let `default` = RewriteHotkey(
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(controlKey | optionKey)
    )
    static let off = RewriteHotkey(keyCode: nil, modifiers: 0)

    /// Carbon RegisterEventHotKey arguments.
    var spec: (keyCode: UInt32, modifiers: UInt32)? {
        keyCode.map { ($0, modifiers) }
    }

    // MARK: - display

    /// ⌃⌥⇧⌘ glyphs in Apple order, then the key name — e.g. "⌃⌥ R".
    var label: String {
        guard let keyCode else { return "未设置" }
        let glyphs = Self.modifierGlyphs(modifiers)
        let name = Self.keyName(keyCode)
        return glyphs.isEmpty ? name : "\(glyphs) \(name)"
    }

    static func modifierGlyphs(_ mask: UInt32) -> String {
        var s = ""
        if mask & UInt32(controlKey) != 0 { s += "⌃" }
        if mask & UInt32(optionKey) != 0 { s += "⌥" }
        if mask & UInt32(shiftKey) != 0 { s += "⇧" }
        if mask & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    /// Non-translated special keys; letters/digits/punctuation go through
    /// UCKeyTranslate so the label matches the user's layout.
    private static let specialKeyNames: [UInt32: String] = {
        var t: [UInt32: String] = [
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_Escape): "⎋",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Home): "⇱",
            UInt32(kVK_End): "⇲",
            UInt32(kVK_PageUp): "⇞",
            UInt32(kVK_PageDown): "⇟",
        ]
        for (i, kc) in functionKeyCodes.enumerated() {
            t[kc] = "F\(i + 1)"
        }
        return t
    }()

    /// macOS virtual key codes for F1…F20.
    static let functionKeyCodes: [UInt32] = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
        UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
        UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20),
    ]

    /// US-layout fallback when UCKeyTranslate is unavailable.
    private static let ansiKeyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Grave): "`",
    ]

    static func keyName(_ keyCode: UInt32) -> String {
        if let special = specialKeyNames[keyCode] { return special }
        if let c = translatedChar(keyCode), !c.isEmpty {
            return c.uppercased()
        }
        return ansiKeyNames[keyCode] ?? "?"
    }

    /// The unmodified character this key types under the current layout.
    private static func translatedChar(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?
            .takeRetainedValue(),
            let raw = TISGetInputSourceProperty(
                source, kTISPropertyUnicodeKeyLayoutData
            )
        else { return nil }
        // the property is a CFDataRef handed back unretained
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        let layout = unsafeBitCast(
            CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self
        )
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        let status = UCKeyTranslate(
            layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &dead, chars.count, &len, &chars
        )
        guard status == noErr, len > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: len)
    }

    // MARK: - validation

    enum ValidationResult: Equatable {
        case ok
        /// bare keys (except function keys) would shadow normal typing
        case needsModifier
        /// collides with system shortcuts or common editing operations
        case reserved
    }

    /// (keyCode, minimal modifier mask) pairs we refuse to take over.
    private static let reservedCombos: [(UInt32, UInt32)] = [
        (UInt32(kVK_ANSI_Q), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_W), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_H), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_M), UInt32(cmdKey)),
        (UInt32(kVK_Tab), UInt32(cmdKey)),
        (UInt32(kVK_Space), UInt32(cmdKey)),
        (UInt32(kVK_Space), UInt32(controlKey)),
        (UInt32(kVK_ANSI_C), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_V), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_X), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_Z), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_A), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_S), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_F), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_N), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_O), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_P), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_T), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_Z), UInt32(cmdKey | shiftKey)),
        (UInt32(kVK_ANSI_Comma), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_Grave), UInt32(cmdKey)),
    ]

    static func validate(keyCode: UInt32, modifiers: UInt32)
        -> ValidationResult
    {
        let strong = UInt32(controlKey | optionKey | cmdKey)
        if modifiers & strong == 0 && !functionKeyCodes.contains(keyCode) {
            return .needsModifier
        }
        for (kc, mask) in reservedCombos
        where keyCode == kc && modifiers & mask == mask {
            return .reserved
        }
        return .ok
    }

    /// NSEvent modifierFlags → Carbon mask.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }
}

extension RewriteHotkey {
    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }

    /// Accepts the keyed object or the legacy preset string so settings
    /// written by older builds keep decoding. (In an extension so the
    /// memberwise init is still synthesized.)
    init(from decoder: Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            switch legacy {
            case "ctrlOptR":
                self = .`default`
            case "ctrlOptE":
                self.init(
                    keyCode: UInt32(kVK_ANSI_E),
                    modifiers: UInt32(controlKey | optionKey)
                )
            case "optCmdJ":
                self.init(
                    keyCode: UInt32(kVK_ANSI_J),
                    modifiers: UInt32(optionKey | cmdKey)
                )
            case "off":
                self = .off
            default:
                self = .`default`
            }
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try c.decodeIfPresent(UInt32.self, forKey: .keyCode),
            modifiers: try c.decodeIfPresent(UInt32.self, forKey: .modifiers) ?? 0
        )
    }
}

/// Thin wrapper over Carbon RegisterEventHotKey — works regardless of which
/// app is frontmost (the rewrite panel never activates, same as the card).
final class GlobalHotkey {
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Registers the combo; returns the Carbon status so the caller can
    /// surface conflicts (eventHotKeyExistsErr = taken by another app).
    @discardableResult
    func set(_ spec: (keyCode: UInt32, modifiers: UInt32)?) -> OSStatus {
        unregister()
        guard let spec else { return noErr }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: 0x4445_4149, id: 1) // 'DEAI'
        return RegisterEventHotKey(
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
