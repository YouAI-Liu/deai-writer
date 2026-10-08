import AppKit
import Combine
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
    /// UI language — pushed by the controller / capture fixture so an open
    /// panel re-renders live on a settings change.
    @Published var lang: UILanguage = .zh
    /// "请先在设置中配置 AI 服务" — the error then gets an 打开设置 button.
    @Published var showOpenSettings = false
    /// Retrying only makes sense with a captured rewrite context.
    @Published var canRetry = false

    // 记住改法: word-level changed pairs (original → result) offered as
    // checkboxes once a result arrives.
    @Published var rememberPairs: [RewriteDiff.Pair] = []
    /// Checked pair indexes — everything starts checked.
    @Published var rememberChecked: Set<Int> = []
    @Published var rememberExpanded = false
    /// Set after 加入词库 succeeds — the button becomes a confirmation.
    @Published var rememberSaved = false

    var onAccept: () -> Void = {}
    var onRetry: () -> Void = {}
    var onCancel: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    /// Checked `Pair`s the user wants as replace lexicon entries.
    var onAddLexiconPairs: ([RewriteDiff.Pair]) -> Void = { _ in }
}

/// Non-activating borderless panel for the AI rewrite flow — same
/// positioning / Esc / outside-click patterns as SuggestionCardPanel.
/// Main-thread confined.
final class RewritePanel {
    let model = RewritePanelModel()

    private var panel: NSPanel?
    private var preferredTopLeft = CGPoint.zero
    private var anchorScreen: NSScreen?
    private var escMonitor: Any?
    private var globalEscMonitor: Any?
    private var outsideMonitor: Any?
    /// Refit when view-only state changes (e.g. 记住改法 expansion).
    private var modelCancellable: AnyCancellable?

    /// Fires on every dismissal — the controller cancels the in-flight
    /// request and clears the debug state here.
    var onDismissed: (() -> Void)?

    var isShowing: Bool { panel != nil }

    func show(near rect: CGRect) {
        dismiss()
        let view = RewritePanelView(model: model)
        let host = NSHostingView(rootView: view)
        // The panel owns its size; SwiftUI must not grow the window by
        // changing its minimum size before our anchored refit runs.
        host.sizingOptions = [.intrinsicContentSize]
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
        anchorScreen = NSScreen.screens.first(where: {
            $0.frame.contains(rect.origin)
        }) ?? NSScreen.main
        if let screen = anchorScreen {
            let f = screen.visibleFrame
            if origin.y < f.minY {
                origin.y = rect.maxY + 6
            }
        }
        preferredTopLeft = CGPoint(x: origin.x, y: origin.y + host.fittingSize.height)
        panel.setFrame(fittedFrame(size: host.fittingSize), display: false)
        panel.orderFront(nil)
        self.panel = panel
        modelCancellable = model.objectWillChange.sink { [weak self] _ in
            self?.update()
        }

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

    private func fittedFrame(size: NSSize) -> CGRect {
        var frame = CGRect(
            x: preferredTopLeft.x, y: preferredTopLeft.y - size.height,
            width: size.width, height: size.height
        )
        if let visible = anchorScreen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX + 4),
                                 visible.maxX - size.width - 4)
            frame.origin.y = min(max(frame.minY, visible.minY + 4),
                                 visible.maxY - size.height - 4)
        }
        return frame
    }

    /// Refit from the saved top edge, moving only as needed to stay on screen.
    private func refit() {
        guard let panel, let host = panel.contentView as? NSHostingView<RewritePanelView>
        else { return }
        host.layout()
        panel.setFrame(fittedFrame(size: host.fittingSize), display: true)
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
        modelCancellable = nil
        let wasShowing = panel != nil
        panel?.orderOut(nil)
        panel = nil
        if wasShowing { onDismissed?() }
    }
}

struct RewritePanelView: View {
    @ObservedObject var model: RewritePanelModel
    private var lang: UILanguage { model.lang }
    private static let panelWidth: CGFloat = 420
    private static let contentPadding: CGFloat = 22

    /// The panel fits its content, so a ScrollView needs a concrete viewport.
    /// Reserve room for its scrollbar and match the 13pt body font.
    static func textViewportHeight(_ text: String) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: panelWidth - contentPadding * 2 - 12,
                         height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        return min(160, max(20, ceil(bounds.height) + 4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.t(.rewriteTitle, lang))
                    .font(DeAIDesign.font(16, weight: .semibold))
                Spacer()
                Button { model.onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(DeAIDesign.font(11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DeAIDesign.muted)
                .deaiTooltip(L10n.t(.closeTooltip, lang))
                .accessibilityLabel(L10n.t(.closeTooltip, lang))
            }
            switch model.phase {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t(.rewriting, lang)).foregroundStyle(DeAIDesign.muted)
                    Spacer()
                    Button(L10n.t(.cancelButton, lang)) { model.onCancel() }
                }
            case .result:
                labeled(L10n.t(.originalLabel, lang), text: model.original, muted: true)
                Rectangle().fill(DeAIDesign.border).frame(height: 0.5)
                labeled(L10n.t(.rewriteLabel, lang), text: model.result, muted: false)
                switch RewriteDiff.rememberSection(
                    changed: model.result != model.original,
                    pairs: model.rememberPairs
                ) {
                case .list:
                    rememberBlock
                case .note:
                    // changed but unsplittable — say so instead of hiding
                    Text(L10n.t(.rememberTooLarge, lang))
                        .font(DeAIDesign.font(11))
                        .foregroundStyle(DeAIDesign.muted)
                case .hidden:
                    EmptyView()
                }
                HStack(spacing: 16) {
                    Button(L10n.t(.replaceButton, lang)) { model.onAccept() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(DeAIButtonStyle(compact: true))
                    Button(L10n.t(.copyButton, lang)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            model.result, forType: .string
                        )
                    }
                    Button(L10n.t(.retryButton, lang)) { model.onRetry() }
                    Spacer(minLength: 0)
                    Button(L10n.t(.cancelButton, lang)) { model.onCancel() }
                }
                .font(DeAIDesign.font(11))
                .buttonStyle(.plain)
                .foregroundStyle(DeAIDesign.muted)
            case .error:
                Text(model.errorMessage)
                    .font(DeAIDesign.font(12))
                    .foregroundStyle(DeAIDesign.danger)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    if model.showOpenSettings {
                        Button(L10n.t(.openSettings, lang)) { model.onOpenSettings() }
                            .buttonStyle(DeAIButtonStyle(compact: true))
                    }
                    if model.canRetry {
                        Button(L10n.t(.retryButton, lang)) { model.onRetry() }
                    }
                    Spacer(minLength: 0)
                    Button(L10n.t(.cancelButton, lang)) { model.onCancel() }
                }
                .font(DeAIDesign.font(11))
                .buttonStyle(.plain)
                .foregroundStyle(DeAIDesign.muted)
            case .noChange:
                Text(L10n.t(.noChange, lang))
                    .font(DeAIDesign.font(12))
                    .foregroundStyle(DeAIDesign.muted)
                HStack {
                    Spacer()
                    Button(L10n.t(.closeTooltip, lang)) { model.onCancel() }
                        .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                }
            }
        }
        .padding(Self.contentPadding)
        .frame(width: Self.panelWidth)
        .background(DeAIDesign.background, in: RoundedRectangle(cornerRadius: DeAIDesign.radius))
        .clipShape(RoundedRectangle(cornerRadius: DeAIDesign.radius))
        .overlay {
            RoundedRectangle(cornerRadius: DeAIDesign.radius)
                .strokeBorder(DeAIDesign.border, lineWidth: 0.5)
        }
        .foregroundStyle(DeAIDesign.text)
        .font(DeAIDesign.font())
        // child controls (DeAIToggleStyle etc.) read the env — the hosting
        // NSView was created once, so the language is pushed via the model
        .environment(\.deaiUILanguage, lang)
        .onExitCommand { model.onCancel() }
    }

    /// 记住改法: expands to the word-level changed pairs as checkboxes;
    /// 加入词库 stores the checked ones as replace lexicon entries.
    private var rememberBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                // Match the native panel's immediate resize when content changes.
                model.rememberExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(
                        systemName: model.rememberExpanded
                            ? "chevron.down" : "chevron.right"
                    )
                    .font(DeAIDesign.font(9, weight: .semibold))
                    Text(
                        model.rememberSaved
                            ? L10n.t(.rememberSaved, lang)
                            : L10n.f(.rememberToggle, lang, model.rememberPairs.count)
                    )
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(DeAIDesign.muted)
            .font(DeAIDesign.font(11))
            .accessibilityLabel(L10n.t(.rememberA11y, lang))

            if model.rememberExpanded && !model.rememberSaved {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.rememberPairs.indices, id: \.self) { i in
                        let pair = model.rememberPairs[i]
                        Toggle(
                            isOn: Binding(
                                get: { model.rememberChecked.contains(i) },
                                set: { on in
                                    if on {
                                        model.rememberChecked.insert(i)
                                    } else {
                                        model.rememberChecked.remove(i)
                                    }
                                }
                            )
                        ) {
                            Text(
                                pair.to.isEmpty
                                    ? L10n.f(.pairDelete, lang, pair.from)
                                    : L10n.f(.pairReplace, lang, pair.from, pair.to)
                            )
                            .font(DeAIDesign.font(11))
                        }
                        .toggleStyle(DeAIToggleStyle())
                    }
                    HStack {
                        Spacer()
                        Button(L10n.t(.addToLexicon, lang)) {
                            let picked = model.rememberPairs.indices
                                .filter { model.rememberChecked.contains($0) }
                                .map { model.rememberPairs[$0] }
                            guard !picked.isEmpty else { return }
                            model.onAddLexiconPairs(picked)
                        }
                        .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                        .disabled(model.rememberChecked.isEmpty)
                        .opacity(model.rememberChecked.isEmpty ? 0.4 : 1)
                    }
                }
                .padding(10)
                .background(
                    DeAIDesign.sidebar,
                    in: RoundedRectangle(cornerRadius: DeAIDesign.controlRadius)
                )
            }
        }
    }

    private func labeled(_ label: String, text: String, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(DeAIDesign.font(10))
                .foregroundStyle(DeAIDesign.muted)
            ScrollView {
                Text(text)
                    .font(DeAIDesign.font(13))
                    .foregroundStyle(muted ? DeAIDesign.secondaryText : DeAIDesign.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
            }
            .frame(height: Self.textViewportHeight(text))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
