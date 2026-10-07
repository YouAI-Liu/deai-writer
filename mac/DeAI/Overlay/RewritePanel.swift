import AppKit
import SwiftUI

/// Observable state behind the rewrite panel. Written only on main.
final class RewritePanelModel: ObservableObject {
    enum Phase: String {
        case loading
        case result
        case error
        case noChange
    }

    @Published var phase: Phase = .loading
    @Published var original = ""
    @Published var result = ""
    @Published var errorMessage = ""
    /// "请先在设置中配置 AI 服务" — the error then gets an 打开设置 button.
    @Published var showOpenSettings = false
    /// Retrying only makes sense with a captured rewrite context.
    @Published var canRetry = false

    var onAccept: () -> Void = {}
    var onRetry: () -> Void = {}
    var onCancel: () -> Void = {}
    var onOpenSettings: () -> Void = {}
}

/// Non-activating borderless panel for the AI rewrite flow — same
/// positioning / Esc / outside-click patterns as SuggestionCardPanel.
/// Main-thread confined.
final class RewritePanel {
    let model = RewritePanelModel()

    private var panel: NSPanel?
    private var escMonitor: Any?
    private var globalEscMonitor: Any?
    private var outsideMonitor: Any?

    /// Fires on every dismissal — the controller cancels the in-flight
    /// request and clears the debug state here.
    var onDismissed: (() -> Void)?

    var isShowing: Bool { panel != nil }

    func show(near rect: CGRect) {
        dismiss()
        let view = RewritePanelView(model: model)
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
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.isReleasedWhenClosed = false
        panel.contentView = host

        var origin = CGPoint(
            x: rect.minX,
            y: rect.minY - host.fittingSize.height - 6
        )
        if let screen = NSScreen.screens.first(where: {
            $0.frame.contains(rect.origin)
        }) ?? NSScreen.main {
            let f = screen.visibleFrame
            if origin.y < f.minY {
                origin.y = rect.maxY + 6
            }
            origin.x = min(
                max(origin.x, f.minX + 4),
                f.maxX - host.fittingSize.width - 4
            )
        }
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        self.panel = panel

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] e in
            if e.keyCode == 53 { self?.dismiss(); return nil }
            return e
        }
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] e in
            if e.keyCode == 53 {
                DispatchQueue.main.async { self?.dismiss() }
            }
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] e in
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.panel else { return }
                if !panel.frame.contains(e.locationInWindow) {
                    self.dismiss()
                }
            }
        }
    }

    /// Phase transitions resize the content — refit, keeping the top edge
    /// pinned so the panel grows downward from its anchor.
    private func refit() {
        guard let panel, let host = panel.contentView as? NSHostingView<RewritePanelView>
        else { return }
        host.layout()
        let fit = host.fittingSize
        var f = panel.frame
        f.origin.y = f.maxY - fit.height
        f.size = fit
        panel.setFrame(f, display: true)
    }

    func update() {
        // SwiftUI needs a tick to lay out before fittingSize is correct
        DispatchQueue.main.async { [weak self] in self?.refit() }
    }

    func dismiss() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        if let m = globalEscMonitor {
            NSEvent.removeMonitor(m)
            globalEscMonitor = nil
        }
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        let wasShowing = panel != nil
        panel?.orderOut(nil)
        panel = nil
        if wasShowing { onDismissed?() }
    }
}

struct RewritePanelView: View {
    @ObservedObject var model: RewritePanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI 改写")
                    .font(DeAIDesign.font(16, weight: .semibold))
                Spacer()
                Button { model.onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(DeAIDesign.font(11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
                .accessibilityLabel("关闭")
            }
            switch model.phase {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("AI 改写中…").foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Button("取消") { model.onCancel() }
                }
            case .result:
                labeled("原文", text: model.original, muted: true)
                Rectangle().fill(.white.opacity(0.10)).frame(height: 0.5)
                labeled("改写", text: model.result, muted: false)
                HStack(spacing: 16) {
                    Button("替换") { model.onAccept() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(DeAIButtonStyle(inverted: true))
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            model.result, forType: .string
                        )
                    }
                    Button("重试") { model.onRetry() }
                    Spacer(minLength: 0)
                    Button("取消") { model.onCancel() }
                }
                .font(DeAIDesign.font(11))
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
            case .error:
                Text(model.errorMessage)
                    .font(DeAIDesign.font(12))
                    .foregroundStyle(.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    if model.showOpenSettings {
                        Button("打开设置") { model.onOpenSettings() }
                            .buttonStyle(DeAIButtonStyle(inverted: true))
                    }
                    if model.canRetry {
                        Button("重试") { model.onRetry() }
                    }
                    Spacer(minLength: 0)
                    Button("取消") { model.onCancel() }
                }
                .font(DeAIDesign.font(11))
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
            case .noChange:
                Text("没有需要修改的地方")
                    .font(DeAIDesign.font(12))
                    .foregroundStyle(.white.opacity(0.55))
                HStack {
                    Spacer()
                    Button("关闭") { model.onCancel() }
                        .buttonStyle(DeAIButtonStyle(compact: true))
                }
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DeAIDesign.ink, in: RoundedRectangle(cornerRadius: DeAIDesign.radius))
        .clipShape(RoundedRectangle(cornerRadius: DeAIDesign.radius))
        .overlay {
            RoundedRectangle(cornerRadius: DeAIDesign.radius)
                .strokeBorder(DeAIDesign.componentOutline, lineWidth: 0.5)
        }
        .foregroundStyle(DeAIDesign.paper)
        .font(DeAIDesign.font())
        .colorScheme(.dark)
        .onExitCommand { model.onCancel() }
    }

    private func labeled(_ label: String, text: String, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(DeAIDesign.font(10))
                .foregroundStyle(.white.opacity(0.4))
            ScrollView {
                Text(text)
                    .font(DeAIDesign.font(13))
                    .foregroundStyle(muted ? .white.opacity(0.55) : DeAIDesign.paper)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        }
    }
}
