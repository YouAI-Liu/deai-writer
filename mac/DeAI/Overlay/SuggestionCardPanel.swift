import AppKit
import OSLog
import SwiftUI

/// Non-activating panel hosting the SwiftUI suggestion card. Closes on Esc,
/// on clicks outside, and on app switch (handled by the controller).
/// Main-thread confined.
final class SuggestionCardPanel {
    private let log = Logger(subsystem: "com.local.deai", category: "overlay")

    private var panel: NSPanel?
    private var escMonitor: Any?
    private var globalEscMonitor: Any?
    private var outsideMonitor: Any?
    private var onDismiss: (() -> Void)?

    /// The finding the open card is bound to (nil when closed) — surfaced in
    /// the debug state dump.
    private(set) var current: (finding: Finding, matchedText: String)?

    func show(
        finding: Finding,
        matchedText: String,
        near rect: CGRect,
        onApply: @escaping (String) -> Void,
        onRewrite: @escaping () -> Void,
        onIgnore: @escaping () -> Void,
        onDisableRule: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        dismiss()
        self.onDismiss = onDismiss
        current = (finding, matchedText)

        let view = SuggestionCardView(
            finding: finding,
            matchedText: matchedText,
            onApply: { [weak self] s in onApply(s); self?.dismiss() },
            // the controller re-derives the scope from the finding — the
            // card must be gone before the rewrite panel anchors
            onRewrite: { [weak self] in self?.dismiss(); onRewrite() },
            onIgnore: { [weak self] in onIgnore(); self?.dismiss() },
            onDisableRule: { [weak self] in onDisableRule(); self?.dismiss() },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let host = NSHostingView(rootView: view)
        host.setFrameSize(host.fittingSize)

        let panel = NSPanel(
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

    func dismiss() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        if let m = globalEscMonitor {
            NSEvent.removeMonitor(m)
            globalEscMonitor = nil
        }
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
        current = nil
        onDismiss?()
        onDismiss = nil
    }
}
