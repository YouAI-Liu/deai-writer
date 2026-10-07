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
        guard !applicationStarted else { return }
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
        .padding(compact ? 18 : 22)
        .frame(width: compact ? 270 : 356, alignment: .leading)
        .background(DeAIDesign.ink, in: RoundedRectangle(cornerRadius: compact ? 36 : DeAIDesign.radius))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 36 : DeAIDesign.radius))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 36 : DeAIDesign.radius)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
        .foregroundStyle(DeAIDesign.paper)
        .font(DeAIDesign.font())
        .colorScheme(.dark)
        .opacity(model.visible ? 1 : 0)
        .scaleEffect(reduceMotion || model.visible ? 1 : 0.96, anchor: .top)
        .animation(reduceMotion ? nil : DeAIDesign.motion(false), value: compact)
        .animation(DeAIDesign.motion(reduceMotion), value: model.visible)
        .frame(width: 356, alignment: .topLeading)
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

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Text(verbatim: model.finding.message)
                    .font(DeAIDesign.font(16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { model.onDismiss() } label: {
                    Image(systemName: "xmark").font(DeAIDesign.font(11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
                .accessibilityLabel("关闭建议")
            }
            comparisons
            Rectangle().fill(.white.opacity(0.10)).frame(height: 0.5)
            HStack(spacing: 16) {
                Spacer(minLength: 0)
                Button("忽略") { model.onIgnore() }
                Button("停用规则") { model.onDisableRule() }
            }
            .font(DeAIDesign.font(11)).buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .disabled(model.applicationStarted)
        }
    }

    private var comparisons: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.matchedText.isEmpty {
                comparison("原文", text: model.matchedText, muted: true)
            }
            if case let .diff(result) = model.phase {
                if !result.isEmpty {
                    comparison("改写", text: result, muted: false)
                    applyButton(result)
                }
            } else {
                ForEach(Array(model.finding.suggestions.enumerated()), id: \.offset) { _, suggestion in
                    if !suggestion.isEmpty { comparison("建议", text: suggestion, muted: false) }
                    applyButton(suggestion)
                }
            }
        }
    }

    private func comparison(_ label: String, text: String, muted: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label).font(DeAIDesign.font(10)).foregroundStyle(.white.opacity(0.4))
                .frame(width: 24, alignment: .leading).padding(.top, 2)
            Text(verbatim: text)
                .font(DeAIDesign.font(13, weight: .regular))
                .foregroundStyle(muted ? .white.opacity(0.55) : DeAIDesign.paper)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func applyButton(_ suggestion: String) -> some View {
        Button { model.apply(suggestion) } label: {
            HStack {
                if model.phase == .loading && (model.selectedReplacement == nil || model.selectedReplacement == suggestion) {
                    if reduceMotion {
                        Image(systemName: "ellipsis")
                    } else {
                        ProgressView().controlSize(.small).colorScheme(.light)
                    }
                    Text("正在应用")
                } else {
                    Text(suggestion.isEmpty ? "删除这段文字" : "替换")
                }
                Spacer()
                Image(systemName: "arrow.right").font(DeAIDesign.font(13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: DeAIDesign.contentDuration), value: model.phase)
        }
        .buttonStyle(DeAIButtonStyle(inverted: true))
        .disabled(model.applicationStarted)
        .accessibilityLabel(suggestion.isEmpty ? "删除这段文字" : "替换为：\(suggestion)")
    }

    private var completion: some View {
        HStack(spacing: 12) {
            Image(systemName: model.phase == .success ? "checkmark" : "exclamationmark")
                .font(DeAIDesign.font(13, weight: .medium))
                .foregroundStyle(DeAIDesign.ink)
                .frame(width: 30, height: 30)
                .background(DeAIDesign.paper, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(model.phase == .success ? "已应用" : "未能应用")
                    .font(DeAIDesign.font(14, weight: .semibold))
                if model.phase == .failure {
                    Text("重新检查后再试。")
                        .font(DeAIDesign.font(10)).foregroundStyle(.white.opacity(0.48))
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
