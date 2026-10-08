import AppKit
import OSLog
import SwiftUI

/// Non-activating panel hosting the SwiftUI suggestion card. Closes on Esc,
/// on clicks outside, and on app switch (handled by the controller).
/// Main-thread confined.
final class SuggestionCardPanel {
    private let log = Logger(subsystem: "com.local.deai", category: "overlay")

    private var panel: NSPanel?
    private var model: SuggestionCardModel?

    var isPresentingApplication: Bool { model?.applicationStarted == true }
    private var escMonitor: Any?
    private var globalEscMonitor: Any?
    private var outsideMonitor: Any?
    private var onDismiss: (() -> Void)?

    /// The finding the open card is bound to (nil when closed) — surfaced in
    /// the debug state dump.
    private(set) var current: (finding: Finding, matchedText: String)?

    /// UI language pushed to the open card (settings change applies live).
    var lang: UILanguage = .zh {
        didSet { model?.lang = lang }
    }

    /// - Parameters:
    ///   - sessionStep: selection-check session position (`nil` hides the
    ///     stepper); `onStep` receives ±1 from the ‹ › buttons.
    ///   - keepOpenOnAction: session cards advance instead of closing on
    ///     忽略 / 停用此规则, so those buttons must not dismiss the panel.
    func show(
        finding: Finding,
        matchedText: String,
        near rect: CGRect,
        sessionStep: (index: Int, count: Int)? = nil,
        onStep: ((Int) -> Void)? = nil,
        keepOpenOnAction: Bool = false,
        onApply: @escaping (String, @escaping (Bool) -> Void) -> Void,
        onRewrite: @escaping () -> Void,
        onIgnore: @escaping () -> Void,
        onDisableRule: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onAddKeep: (() -> Void)? = nil,
        onRememberFix: (() -> Void)? = nil,
        onEditLexicon: (() -> Void)? = nil
    ) {
        if panel == nil { dismiss() }
        self.onDismiss = onDismiss
        current = (finding, matchedText)

        let model: SuggestionCardModel
        let host: NSHostingView<SuggestionCardView>
        let panel: NSPanel
        let reusing = self.panel != nil
        if let existing = self.model,
           let existingPanel = self.panel,
           let existingHost = existingPanel.contentView as? NSHostingView<SuggestionCardView> {
            model = existing
            panel = existingPanel
            host = existingHost
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : DeAIDesign.motion(false)) {
                model.update(finding: finding, matchedText: matchedText)
            }
        } else {
            model = SuggestionCardModel(finding: finding, matchedText: matchedText)
            host = NSHostingView(rootView: SuggestionCardView(model: model))
            host.setFrameSize(host.fittingSize)
            panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: host.fittingSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.contentView = host
            self.model = model
        }
        model.lang = lang
        if let sessionStep {
            model.setSessionStep(index: sessionStep.index, count: sessionStep.count)
        } else {
            model.setSessionStep(index: 0, count: 0)
        }
        model.onStep = { onStep?($0) }
        // BUG-01 diagnostics: did the card panel steal key focus at click?
        model.onApply = { [weak self] replacement, completion in
            TextReplacer.dbgLog(
                "card apply click: panel.isKeyWindow=\(self?.panel?.isKeyWindow ?? false)"
            )
            onApply(replacement, completion)
        }
        // the controller re-derives the scope from the finding — the
        // card must be gone before the rewrite panel anchors
        model.onRewrite = { [weak self] in self?.dismiss(); onRewrite() }
        model.onIgnore = { [weak self] in
            onIgnore()
            if !keepOpenOnAction { self?.dismiss() }
        }
        model.onDisableRule = { [weak self] in
            onDisableRule()
            if !keepOpenOnAction { self?.dismiss() }
        }
        // lexicon …-menu actions: they mutate the lexicon then re-check —
        // keep the card open when keepOpenOnAction is set (session cards),
        // close it otherwise so the fresh underline state is clickable
        model.onAddKeep = { [weak self] in
            onAddKeep?()
            if !keepOpenOnAction { self?.dismiss() }
        }
        model.onRememberFix = { [weak self] in
            onRememberFix?()
            if !keepOpenOnAction { self?.dismiss() }
        }
        model.onEditLexicon = { [weak self] in
            self?.dismiss()
            onEditLexicon?()
        }
        model.onDismiss = { [weak self] in self?.dismiss() }
        host.layoutSubtreeIfNeeded()
        host.setFrameSize(host.fittingSize)
        panel.setContentSize(host.fittingSize)

        // anchor below the underline rect; flip above if it would go off screen
        var origin = CGPoint(x: rect.minX, y: rect.minY - host.fittingSize.height - 6)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(rect.origin) })
            ?? NSScreen.main {
            let f = screen.visibleFrame
            if origin.y < f.minY {
                origin.y = rect.maxY + 6
            }
            origin.x = min(max(origin.x, f.minX + 4), f.maxX - host.fittingSize.width - 4)
        }
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        self.panel = panel

        if reusing { return }

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.dismiss(); return nil }
            return e
        }
        // The host app stays frontmost (non-activating panel), so Esc usually
        // never reaches our local monitor — also watch global keyDown while
        // the card is up (BUG-09).
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] e in
            if e.keyCode == 53 {
                DispatchQueue.main.async { self?.dismiss() }
            }
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] e in
            // global monitor handlers run on an arbitrary thread
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.panel else { return }
                // for windowless events locationInWindow is screen coords
                if !panel.frame.contains(e.locationInWindow) { self.dismiss() }
            }
        }
        log.debug("suggestion card shown for \(finding.ruleId)")
    }

    /// The selection-check "no findings" card: same panel, empty variant.
    /// `flash` shows "仍未发现问题" (a 重新检测 came back empty again).
    func showEmpty(
        near rect: CGRect,
        sensitivity: Int,
        flash: Bool,
        onSensitivityChange: @escaping (Int) -> Void,
        onRecheck: @escaping () -> Void,
        onRewrite: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        if panel == nil { dismiss() }
        self.onDismiss = onDismiss
        current = nil

        // the model needs a finding — reuse a placeholder when creating
        let placeholder = Finding(
            category: .grammar, ruleId: "", message: "",
            start: 0, end: 0, suggestions: [], tier: 1
        )
        let model: SuggestionCardModel
        let host: NSHostingView<SuggestionCardView>
        let panel: NSPanel
        let reusing = self.panel != nil
        if let existing = self.model,
           let existingPanel = self.panel,
           let existingHost = existingPanel.contentView as? NSHostingView<SuggestionCardView> {
            model = existing
            panel = existingPanel
            host = existingHost
            model.presentEmpty(sensitivity: sensitivity, flash: flash)
        } else {
            model = SuggestionCardModel(finding: placeholder, matchedText: "")
            model.presentEmpty(sensitivity: sensitivity, flash: flash)
            host = NSHostingView(rootView: SuggestionCardView(model: model))
            host.setFrameSize(host.fittingSize)
            panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: host.fittingSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.contentView = host
            self.model = model
        }
        model.lang = lang
        model.setSessionStep(index: 0, count: 0)
        model.onSensitivityChange = onSensitivityChange
        model.onRecheck = onRecheck
        model.onRewrite = { [weak self] in self?.dismiss(); onRewrite() }
        model.onDismiss = { [weak self] in self?.dismiss() }
        host.layoutSubtreeIfNeeded()
        host.setFrameSize(host.fittingSize)
        panel.setContentSize(host.fittingSize)

        var origin = CGPoint(x: rect.minX, y: rect.minY - host.fittingSize.height - 6)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(rect.origin) })
            ?? NSScreen.main {
            let f = screen.visibleFrame
            if origin.y < f.minY {
                origin.y = rect.maxY + 6
            }
            origin.x = min(max(origin.x, f.minX + 4), f.maxX - host.fittingSize.width - 4)
        }
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        self.panel = panel

        if reusing { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.dismiss(); return nil }
            return e
        }
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] e in
            if e.keyCode == 53 {
                DispatchQueue.main.async { self?.dismiss() }
            }
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] e in
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.panel else { return }
                if !panel.frame.contains(e.locationInWindow) { self.dismiss() }
            }
        }
        log.debug("selection-check empty card shown")
    }

    /// Session finished its last finding: show the compact success state —
    /// the view's own auto-dismiss then calls onDismiss.
    func flashSuccess() {
        model?.phase = .success
    }

    func dismiss() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        if let m = globalEscMonitor {
            NSEvent.removeMonitor(m)
            globalEscMonitor = nil
        }
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        model?.cancel()
        model = nil
        panel?.orderOut(nil)
        panel = nil
        current = nil
        onDismiss?()
        onDismiss = nil
    }
}
