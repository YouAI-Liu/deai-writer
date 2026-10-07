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
    @Published private(set) var selectedReplacement: String?
    private(set) var applicationStarted = false
    private var revision = UUID()

    var onApply: (String, @escaping (Bool) -> Void) -> Void = { _, _ in }
    var onRewrite: () -> Void = {}
    var onIgnore: () -> Void = {}
    var onDisableRule: () -> Void = {}
    var onDismiss: () -> Void = {}

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
        selectedReplacement = nil
        applicationStarted = false
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
                if compact {
                    completion
                } else {
                    editor
                        .id(model.finding)
                        .transition(DeAIDesign.contentTransition(reduceMotion).animation(.easeOut(duration: 0.15)))
                }
            }
            .id(compact)
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
                Spacer(minLength: 0)
                Button { model.onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(DeAIDesign.font(9, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DeAIDesign.muted)
                .accessibilityLabel("关闭建议")
            }
            suggestions
            iconRow
        }
    }

    /// Small capsule tag: category dot + name; the finding's full message is
    /// the tooltip / part of the card's accessibility label, not body text.
    private var tag: some View {
        HStack(spacing: 5) {
            Circle().fill(categoryColor).frame(width: 6, height: 6)
            Text(model.finding.category.displayName)
        }
        .font(DeAIDesign.font(10, weight: .medium))
        .foregroundStyle(DeAIDesign.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(DeAIDesign.sidebar, in: Capsule())
        .help(model.finding.message)
        .accessibilityLabel(
            "\(model.finding.category.displayName)：\(model.finding.message)"
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
        .accessibilityLabel("替换为：\(suggestion)")
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
                Text("删除")
                    .font(DeAIDesign.font(10))
                    .foregroundStyle(DeAIDesign.muted.opacity(0.8))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.applicationStarted)
        .accessibilityLabel("删除这段文字")
    }

    // MARK: - icon row

    private var acceptTarget: String? {
        if case let .diff(result) = model.phase {
            return result.isEmpty ? nil : result
        }
        return model.finding.suggestions.first
    }

    private var acceptLabel: String {
        guard let target = acceptTarget else { return "应用" }
        return target.isEmpty ? "删除这段文字" : "替换为：\(target)"
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
            .help(acceptLabel)
            .accessibilityLabel(acceptLabel)

            iconButton("wand.and.stars", label: "AI 改写") { model.onRewrite() }
                .help("AI 改写这一段")
            iconButton("nosign", label: "忽略") { model.onIgnore() }
                .help("忽略")
            Menu {
                Button("停用此规则") { model.onDisableRule() }
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
            .help("更多")
            .accessibilityLabel("更多")
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
            Text(model.phase == .success ? "已应用" : "未能应用")
                .font(DeAIDesign.font(13, weight: .semibold))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
