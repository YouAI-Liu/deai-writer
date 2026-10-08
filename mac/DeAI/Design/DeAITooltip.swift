import AppKit
import SwiftUI

extension View {
    /// AppKit's `.help` only fires for the active app, so it never shows
    /// inside our non-activating panels — this drives the same text through
    /// a tracking area + floating tooltip panel instead.
    func deaiTooltip(_ text: String) -> some View {
        background(TooltipAnchor(text: text))
    }
}

/// Invisible NSView under the control that owns the tooltip. `hitTest`
/// returns nil so clicks always fall through to the button/Menu above.
private struct TooltipAnchor: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipAnchorView {
        TooltipAnchorView(text: text)
    }

    func updateNSView(_ nsView: TooltipAnchorView, context: Context) {
        nsView.text = text
    }

    static func dismantleNSView(_ nsView: TooltipAnchorView, coordinator: ()) {
        nsView.detach()
    }
}

private final class TooltipAnchorView: NSView {
    var text: String {
        didSet { TooltipController.shared.anchorTextChanged(self, text: text) }
    }
    private var tracking: NSTrackingArea?

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // .activeAlways: the card's panel is never key and the app never
        // active, so the area must fire regardless of activation state.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { detach() }
    }

    func detach() {
        TooltipController.shared.hide(anchor: self)
    }

    override func mouseEntered(with event: NSEvent) {
        guard let window else { return }
        let rect = window.convertToScreen(convert(bounds, to: nil))
        TooltipController.shared.schedule(
            text: text, anchorScreenRect: rect, anchor: self
        )
    }

    override func mouseExited(with event: NSEvent) {
        TooltipController.shared.hide(anchor: self)
    }
}

private struct TooltipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DeAIDesign.font(11))
            .foregroundStyle(DeAIDesign.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 224, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                DeAIDesign.background,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DeAIDesign.border, lineWidth: 0.5)
            }
    }
}

/// One reusable borderless panel for every tooltip. Main-thread confined.
final class TooltipController {
    static let shared = TooltipController()

    private var panel: NSPanel?
    private weak var currentAnchor: NSView?
    private var shownRect: CGRect = .zero
    private var shownText = ""
    private var pendingShow: DispatchWorkItem?
    private var lastHideTime: Date?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private init() {}

    func schedule(text: String, anchorScreenRect rect: CGRect, anchor: NSView) {
        if anchor === currentAnchor, panel?.isVisible == true {
            setText(text, anchorScreenRect: rect)
            return
        }
        pendingShow?.cancel()
        currentAnchor = anchor
        installMonitors()
        // Moving icon to icon: keep tooltips instant for a moment after
        // the previous one hid, like AppKit does.
        let instant = lastHideTime.map { Date().timeIntervalSince($0) < 0.3 }
            ?? false
        let work = DispatchWorkItem { [weak self] in
            self?.show(text: text, anchorScreenRect: rect, anchor: anchor)
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (instant ? 0 : 0.5), execute: work
        )
    }

    func hide(anchor: NSView? = nil) {
        if let anchor, let current = currentAnchor, anchor !== current {
            return
        }
        pendingShow?.cancel()
        pendingShow = nil
        currentAnchor = nil
        if panel?.isVisible == true { lastHideTime = Date() }
        panel?.orderOut(nil)
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
    }

    func anchorTextChanged(_ anchor: NSView, text: String) {
        guard anchor === currentAnchor, panel?.isVisible == true else {
            return
        }
        setText(text, anchorScreenRect: shownRect)
    }

    private func show(text: String, anchorScreenRect rect: CGRect, anchor: NSView) {
        guard anchor === currentAnchor, anchor.window != nil else { return }
        currentAnchor = anchor
        setText(text, anchorScreenRect: rect)
        panel?.orderFront(nil)
    }

    private func setText(_ text: String, anchorScreenRect rect: CGRect) {
        shownText = text
        shownRect = rect
        let host: NSHostingView<TooltipLabel>
        if let existing = panel?.contentView as? NSHostingView<TooltipLabel> {
            host = existing
            host.rootView = TooltipLabel(text: text)
        } else {
            host = NSHostingView(rootView: TooltipLabel(text: text))
            let panel = self.panel ?? makePanel()
            panel.contentView = host
            self.panel = panel
        }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        var origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.minY - size.height - 6
        )
        if let screen = NSScreen.screens.first(where: {
            $0.frame.contains(rect.origin)
        }) ?? NSScreen.main {
            let f = screen.visibleFrame
            if origin.y < f.minY { origin.y = rect.maxY + 6 }
            origin.x = min(max(origin.x, f.minX + 4), f.maxX - size.width - 4)
        }
        panel?.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// A click or keystroke anywhere dismisses the tooltip — e.g. the 更多
    /// menu must not open underneath it.
    private func installMonitors() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .keyDown]
            ) { [weak self] e in
                self?.hide()
                return e
            }
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.hide() }
            }
        }
    }
}
