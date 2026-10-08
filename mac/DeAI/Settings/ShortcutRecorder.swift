import AppKit
import Carbon
import SwiftUI

/// "Press the keys yourself" recorder (System Settings / Raycast style) for
/// the global rewrite hotkey. A local event monitor exists only while
/// recording and consumes .keyDown / .flagsChanged.
struct ShortcutRecorder: View {
    @Binding var hotkey: RewriteHotkey
    @Environment(\.deaiUILanguage) private var lang
    /// Recording start/stop — AppController pauses the global hotkey so the
    /// current combo can't fire a rewrite mid-recording.
    var onRecordingChanged: ((Bool) -> Void)?

    @State private var recording: Bool
    @State private var liveModifiers: UInt32
    @State private var error: String?
    @State private var monitor: Any?

    /// `recording`/`heldModifiers` are capture/preview hooks — an injected
    /// recording state renders without installing the monitor.
    init(
        hotkey: Binding<RewriteHotkey>,
        recording: Bool = false,
        heldModifiers: UInt32 = 0,
        onRecordingChanged: ((Bool) -> Void)? = nil
    ) {
        _hotkey = hotkey
        self.onRecordingChanged = onRecordingChanged
        _recording = State(initialValue: recording)
        _liveModifiers = State(initialValue: heldModifiers)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            capsule
            if let error {
                Text(error)
                    .font(DeAIDesign.font(10))
                    .foregroundStyle(DeAIDesign.danger)
            }
        }
        .onDisappear { stopRecording() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSWindow.didResignKeyNotification
            )
        ) { _ in
            // the user clicked away mid-recording — drop it
            stopRecording()
        }
    }

    private var capsule: some View {
        HStack(spacing: 5) {
            if recording {
                ForEach(
                    RewriteHotkey.modifierGlyphs(liveModifiers).map(String.init),
                    id: \.self
                ) { keycap($0) }
                Text(L10n.t(.recordPrompt, lang))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(DeAIDesign.muted)
            } else if let keyCode = hotkey.keyCode {
                ForEach(
                    RewriteHotkey.modifierGlyphs(hotkey.modifiers)
                        .map(String.init),
                    id: \.self
                ) { keycap($0) }
                keycap(RewriteHotkey.keyName(keyCode))
                Button {
                    hotkey = .off
                } label: {
                    Image(systemName: "xmark")
                        .font(DeAIDesign.font(8, weight: .bold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DeAIDesign.muted)
                .help(L10n.t(.clearShortcut, lang))
                .accessibilityLabel(L10n.t(.clearShortcut, lang))
            } else {
                Text(L10n.t(.clickToRecord, lang))
                    .foregroundStyle(DeAIDesign.muted)
            }
        }
        .font(DeAIDesign.font(12, weight: .medium))
        .foregroundStyle(DeAIDesign.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: 120)
        .background(DeAIDesign.sidebar, in: DeAIDesign.pill)
        .overlay {
            DeAIDesign.pill.strokeBorder(
                recording ? DeAIDesign.accent : DeAIDesign.border,
                lineWidth: recording ? 1 : 0.5
            )
        }
        .contentShape(Capsule())
        .onTapGesture {
            if !recording { startRecording() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t(.recorderA11y, lang))
        .accessibilityValue(hotkey.label(lang))
    }

    /// One glyph/key name inside a small keycap — [⌃][⌥][R].
    private func keycap(_ s: String) -> some View {
        Text(s)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                DeAIDesign.surface,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(DeAIDesign.border, lineWidth: 0.5)
            }
    }

    // MARK: - recording

    private func startRecording() {
        recording = true
        error = nil
        liveModifiers = 0
        onRecordingChanged?(true)
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { event in
            self.handle(event)
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        liveModifiers = 0
        error = nil // cancel/end always clears a validation error
        guard recording else { return }
        recording = false
        onRecordingChanged?(false)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let mods = RewriteHotkey.carbonModifiers(event.modifierFlags)
        if event.type == .flagsChanged {
            liveModifiers = mods
            return nil
        }
        let keyCode = UInt32(event.keyCode)
        // bare Esc cancels; bare Delete clears the shortcut
        if mods == 0 {
            switch Int(event.keyCode) {
            case kVK_Escape:
                stopRecording()
                return nil
            case kVK_Delete, kVK_ForwardDelete:
                hotkey = .off
                stopRecording()
                return nil
            default:
                break
            }
        }
        switch RewriteHotkey.validate(keyCode: keyCode, modifiers: mods) {
        case .ok:
            hotkey = RewriteHotkey(keyCode: keyCode, modifiers: mods)
            stopRecording()
        case .needsModifier:
            liveModifiers = mods
            error = L10n.t(.needModifier, lang)
        case .reserved:
            liveModifiers = mods
            error = L10n.t(.reservedCombo, lang)
        }
        return nil
    }
}
