import SwiftUI

/// The diff state is ready for a future rewrite result; no network action is attached.
enum SuggestionCardPhase: Equatable {
    case idle
    case loading
    case diff(String)
    case success
    case failure
}

final class SuggestionCardModel: ObservableObject {
    @Published var finding: Finding
    @Published var matchedText: String
    @Published var phase: SuggestionCardPhase = .idle
    @Published var visible = false
    /// UI language — pushed by the controller / capture fixture so an open
    /// card re-renders live on a settings change.
    @Published var lang: UILanguage = .zh
    @Published private(set) var selectedReplacement: String?
    private(set) var applicationStarted = false
    private var revision = UUID()

    /// Selection-check session: 0-based index / total count (0 = hidden),
    /// driving the compact ‹ n/N › stepper in the card header.
    @Published private(set) var sessionIndex = 0
    @Published private(set) var sessionCount = 0
    /// The "no findings" variant of a selection-check session: 检查完成 tag,
    /// sensitivity slider and 重新检测 button.
    @Published private(set) var isEmptyResult = false
    /// Set after a 重新检测 that found nothing again ("仍未发现问题").
    @Published var emptyFlash = false
    /// Sensitivity shown on the empty variant's slider (1…3).
    @Published var sensitivity = 2

    var onApply: (String, @escaping (Bool) -> Void) -> Void = { _, _ in }
    var onRewrite: () -> Void = {}
    var onIgnore: () -> Void = {}
    var onDisableRule: () -> Void = {}
    var onDismiss: () -> Void = {}
    /// Session stepper (‹ ›): delta -1 / +1.
    var onStep: (Int) -> Void = { _ in }
    /// Empty variant: 重新检测.
    var onRecheck: () -> Void = {}
    /// Empty variant: slider changed (1…3).
    var onSensitivityChange: (Int) -> Void = { _ in }
    /// … menu: add matchedText as a keep entry; re-checks afterwards.
    var onAddKeep: () -> Void = {}
    /// … menu: add matchedText → accepted suggestion as a replace entry.
    var onRememberFix: () -> Void = {}
    /// … menu on personal findings: open Settings on the 个人 tab.
    var onEditLexicon: () -> Void = {}

    init(finding: Finding, matchedText: String) {
        self.finding = finding
        self.matchedText = matchedText
    }

    func update(finding: Finding, matchedText: String) {
        revision = UUID()
        self.finding = finding
        self.matchedText = matchedText
        phase = .idle
        visible = true
        isEmptyResult = false
        emptyFlash = false
        selectedReplacement = nil
        applicationStarted = false
    }

    /// Switch the reused card to the empty ("no findings") variant.
    func presentEmpty(sensitivity: Int, flash: Bool) {
        revision = UUID()
        phase = .idle
        visible = true
        isEmptyResult = true
        emptyFlash = flash
        self.sensitivity = sensitivity
        selectedReplacement = nil
        applicationStarted = false
    }

    /// Session stepper position shown in the header (nil hides it).
    func setSessionStep(index: Int, count: Int) {
        sessionIndex = index
        sessionCount = count
    }

    func apply(_ replacement: String) {
        guard !applicationStarted else {
            TextReplacer.dbgLog("card.apply BLOCKED (already started) repl=\(replacement)")
            return
        }
        TextReplacer.dbgLog("card.apply repl=\(replacement)")
        applicationStarted = true
        selectedReplacement = replacement
        phase = .loading
        let token = revision
        let started = Date()
        onApply(replacement) { [weak self] success in
            // Keep the loader legible even when AX completes synchronously.
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.26 - Date().timeIntervalSince(started))) {
                guard let self, self.revision == token else { return }
                self.phase = success ? .success : .failure
            }
        }
    }

    func cancel() {
        revision = UUID()
        visible = false
    }
}

struct SuggestionCardView: View {
    @ObservedObject var model: SuggestionCardModel
    var autoDismiss = true
    private var lang: UILanguage { model.lang }
    @DeAIReducedMotion private var reduceMotion: Bool

    private var compact: Bool {
        model.phase == .success || model.phase == .failure
    }

    /// The category's underline color resolved for the card's current
    /// appearance (the card follows the system appearance now).
    @Environment(\.colorScheme) private var colorScheme

    private var categoryColor: Color {
        Color(nsColor: DeAIDesign.underlineColor(
            for: model.finding.category,
            appearance: NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.isEmptyResult {
                    emptyBody
                } else if compact {
                    completion
                } else {
                    editor
                        .id(model.finding)
                        .transition(DeAIDesign.contentTransition(reduceMotion).animation(.easeOut(duration: 0.15)))
                }
            }
            .id(compact || model.isEmptyResult)
            .transition(DeAIDesign.contentTransition(reduceMotion).animation(.easeOut(duration: 0.15)))
        }
        .padding(compact ? 12 : 14)
        .frame(width: compact ? 190 : 260, alignment: .leading)
        .background(DeAIDesign.background, in: RoundedRectangle(cornerRadius: DeAIDesign.radius))
        .clipShape(RoundedRectangle(cornerRadius: DeAIDesign.radius))
        .overlay {
            RoundedRectangle(cornerRadius: DeAIDesign.radius)
                .strokeBorder(DeAIDesign.border, lineWidth: 0.5)
        }
        .foregroundStyle(DeAIDesign.text)
        .font(DeAIDesign.font())
        // child controls read the env — the hosting NSView was created once,
        // so the language is pushed through the model
        .environment(\.deaiUILanguage, lang)
        .opacity(model.visible ? 1 : 0)
        .scaleEffect(reduceMotion || model.visible ? 1 : 0.96, anchor: .top)
        .animation(reduceMotion ? nil : DeAIDesign.motion(false), value: compact)
        .animation(DeAIDesign.motion(reduceMotion), value: model.visible)
        .frame(width: 300, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { model.visible = true }
        .onExitCommand { model.onDismiss() }
        .task(id: model.phase) {
            guard compact && autoDismiss else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            model.visible = false
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            model.onDismiss()
        }
    }

    // MARK: - editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                tag
                if model.sessionCount > 0 { stepper }
                Spacer(minLength: 0)
                closeButton
            }
            suggestions
            iconRow
        }
    }

    /// Session stepper "‹ 1/3 ›" shown when the card belongs to a
    /// selection-check session — moves between the scope's findings.
    private var stepper: some View {
        HStack(spacing: 2) {
            Button { model.onStep(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(DeAIDesign.font(9, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .disabled(model.sessionIndex <= 0)
            .deaiTooltip(L10n.t(.stepperPrev, lang))
            Text("\(model.sessionIndex + 1)/\(model.sessionCount)")
                .font(DeAIDesign.font(10, weight: .medium).monospacedDigit())
            Button { model.onStep(1) } label: {
                Image(systemName: "chevron.right")
                    .font(DeAIDesign.font(9, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .disabled(model.sessionIndex >= model.sessionCount - 1)
            .deaiTooltip(L10n.t(.stepperNext, lang))
        }
        .buttonStyle(.plain)
        .foregroundStyle(DeAIDesign.muted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.f(.stepperA11y, lang, model.sessionIndex + 1, model.sessionCount))
        .accessibilityAdjustableAction { direction in
            model.onStep(direction == .increment ? 1 : -1)
        }
    }

    private var closeButton: some View {
        Button { model.onDismiss() } label: {
            Image(systemName: "xmark")
                .font(DeAIDesign.font(9, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DeAIDesign.muted)
        .deaiTooltip(L10n.t(.closeTooltip, lang))
        .accessibilityLabel(L10n.t(.dismissA11y, lang))
    }

    /// Small capsule tag: category dot + name; the finding's full message is
    /// the tooltip / part of the card's accessibility label, not body text.
    private var tag: some View {
        let message = L10n.findingMessage(
            model.finding, matched: model.matchedText, lang: lang
        )
        return HStack(spacing: 5) {
            Circle().fill(categoryColor).frame(width: 6, height: 6)
            Text(model.finding.category.displayName(lang))
        }
        .font(DeAIDesign.font(10, weight: .medium))
        .foregroundStyle(DeAIDesign.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(DeAIDesign.sidebar, in: Capsule())
        .deaiTooltip(message)
        .accessibilityLabel(
            "\(model.finding.category.displayName(lang)): \(message)"
        )
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case let .diff(result) = model.phase {
                if !result.isEmpty {
                    suggestionRow(result)
                }
            } else {
                ForEach(
                    Array(model.finding.suggestions.enumerated()), id: \.offset
                ) { _, suggestion in
                    if suggestion.isEmpty {
                        deletionRow
                    } else {
                        suggestionRow(suggestion)
                    }
                }
            }
        }
    }

    /// Bold suggestion text; tapping the row applies it.
    private func suggestionRow(_ suggestion: String) -> some View {
        Button { model.apply(suggestion) } label: {
            Text(verbatim: suggestion)
                .font(DeAIDesign.font(15, weight: .bold))
                .foregroundStyle(DeAIDesign.text)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.applicationStarted)
        .accessibilityLabel(L10n.f(.replaceWithA11y, lang, suggestion))
    }

    /// Empty suggestion = delete: matched text struck through + 删除 caption.
    private var deletionRow: some View {
        Button { model.apply("") } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: model.matchedText)
                    .font(DeAIDesign.font(15, weight: .bold))
                    .strikethrough()
                    .foregroundStyle(DeAIDesign.muted)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t(.deleteRow, lang))
                    .font(DeAIDesign.font(10))
                    .foregroundStyle(DeAIDesign.muted.opacity(0.8))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.applicationStarted)
        .accessibilityLabel(L10n.t(.deleteTextA11y, lang))
    }

    // MARK: - icon row

    private var acceptTarget: String? {
        if case let .diff(result) = model.phase {
            return result.isEmpty ? nil : result
        }
        return model.finding.suggestions.first
    }

    private var acceptLabel: String {
        guard let target = acceptTarget else { return L10n.t(.applyLabel, lang) }
        return target.isEmpty
            ? L10n.t(.deleteTextA11y, lang)
            : L10n.f(.replaceWithA11y, lang, target)
    }

    private var iconRow: some View {
        HStack(spacing: 8) {
            Button {
                if let target = acceptTarget { model.apply(target) }
            } label: {
                ZStack {
                    Circle().fill(DeAIDesign.acceptGreen)
                        .frame(width: 26, height: 26)
                    if model.phase == .loading {
                        ProgressView()
                            .controlSize(.mini)
                            .colorScheme(.light)
                    } else {
                        Image(systemName: "checkmark")
                            .font(DeAIDesign.font(11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(model.applicationStarted || acceptTarget == nil)
            .deaiTooltip(acceptLabel)
            .accessibilityLabel(acceptLabel)

            iconButton("wand.and.stars", label: L10n.t(.rewriteA11y, lang)) { model.onRewrite() }
                .deaiTooltip(L10n.t(.rewriteTooltip, lang))
            iconButton("nosign", label: L10n.t(.ignoreLabel, lang)) { model.onIgnore() }
                .deaiTooltip(L10n.t(.ignoreLabel, lang))
            Menu {
                if model.finding.category == .personal {
                    Button(L10n.t(.editEntry, lang)) { model.onEditLexicon() }
                } else {
                    Button(L10n.t(.addKeepEntry, lang)) { model.onAddKeep() }
                    if model.finding.suggestions.contains(where: { !$0.isEmpty }) {
                        Button(L10n.t(.rememberFix, lang)) { model.onRememberFix() }
                    }
                }
                Button(L10n.t(.disableRule, lang)) { model.onDisableRule() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(DeAIDesign.font(12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.applicationStarted)
            .deaiTooltip(L10n.t(.moreLabel, lang))
            .accessibilityLabel(L10n.t(.moreLabel, lang))
        }
    }

    private func iconButton(
        _ symbol: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(DeAIDesign.font(12, weight: .medium))
                .foregroundStyle(DeAIDesign.muted)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.applicationStarted)
        .accessibilityLabel(label)
    }

    // MARK: - empty result (selection check found nothing)

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L10n.t(.emptyTag, lang))
                    .font(DeAIDesign.font(10, weight: .medium))
                    .foregroundStyle(DeAIDesign.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DeAIDesign.sidebar, in: Capsule())
                Spacer(minLength: 0)
                closeButton
            }
            Text(model.emptyFlash ? L10n.t(.emptyFlash, lang) : L10n.t(.emptyBody, lang))
                .font(DeAIDesign.font(13, weight: .semibold))
                .foregroundStyle(DeAIDesign.text)
            VStack(alignment: .leading, spacing: 0) {
                Slider(
                    value: Binding(
                        get: { Double(model.sensitivity) },
                        set: { model.onSensitivityChange(Int($0.rounded())) }
                    ),
                    in: 1...3,
                    step: 1
                )
                .tint(DeAIDesign.secondaryText)
                .controlSize(.small)
                .accessibilityLabel(L10n.t(.sensitivityLabel, lang))
                HStack {
                    Text(L10n.t(.sensStrict, lang))
                    Spacer(minLength: 0)
                    Text(L10n.t(.sensStandard, lang))
                    Spacer(minLength: 0)
                    Text(L10n.t(.sensSensitive, lang))
                }
                .font(DeAIDesign.font(9))
                .foregroundStyle(DeAIDesign.muted)
            }
            HStack(spacing: 8) {
                iconButton("wand.and.stars", label: L10n.t(.rewriteA11y, lang)) {
                    model.onRewrite()
                }
                .deaiTooltip(L10n.t(.rewriteSelectionTooltip, lang))
                Spacer(minLength: 0)
                Button(L10n.t(.recheckButton, lang)) { model.onRecheck() }
                    .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
            }
        }
    }

    // MARK: - completion

    private var completion: some View {
        HStack(spacing: 10) {
            Image(systemName: model.phase == .success ? "checkmark" : "exclamationmark")
                .font(DeAIDesign.font(11, weight: .bold))
                .foregroundStyle(model.phase == .success ? DeAIDesign.onAccent : DeAIDesign.text)
                .frame(width: 24, height: 24)
                .background(
                    model.phase == .success ? DeAIDesign.acceptGreen : DeAIDesign.surface,
                    in: Circle()
                )
                .overlay {
                    if model.phase != .success {
                        Circle().strokeBorder(DeAIDesign.border, lineWidth: 0.5)
                    }
                }
            Text(model.phase == .success ? L10n.t(.appliedLabel, lang) : L10n.t(.applyFailedLabel, lang))
                .font(DeAIDesign.font(13, weight: .semibold))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
