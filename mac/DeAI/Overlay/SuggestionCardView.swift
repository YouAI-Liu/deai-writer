import SwiftUI

/// The suggestion card shown when clicking an underline.
struct SuggestionCardView: View {
    let finding: Finding
    let matchedText: String
    var onApply: (String) -> Void
    var onIgnore: () -> Void
    var onDisableRule: () -> Void
    var onDismiss: () -> Void

    private var categoryColor: Color {
        switch finding.category {
        case .grammar: return Color(red: 0.898, green: 0.282, blue: 0.302)
        case .aiToneZh: return Color(red: 0.557, green: 0.306, blue: 0.776)
        case .aiToneEn: return Color(red: 0.0, green: 0.565, blue: 1.0)
        case .markdown: return Color(red: 0.545, green: 0.553, blue: 0.596)
        }
    }

    private var categoryName: String {
        switch finding.category {
        case .grammar: return "语法"
        case .aiToneZh: return "中文 AI 腔"
        case .aiToneEn: return "英文 AI 腔"
        case .markdown: return "Markdown"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(categoryName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor.opacity(0.15))
                    .foregroundStyle(categoryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Tier \(finding.tier)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(finding.ruleId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(finding.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if !matchedText.isEmpty {
                Text(matchedText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !finding.suggestions.isEmpty {
                ForEach(Array(finding.suggestions.enumerated()), id: \.offset) { _, s in
                    Button {
                        onApply(s)
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text(s.isEmpty ? "删除" : s)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Divider()
            HStack {
                Button("AI 改写") {}
                    .disabled(true)
                    .help("即将支持")
                Spacer()
                Button("忽略") { onIgnore() }
                Button("停用此规则") { onDisableRule() }
                    .help("在设置中可重新启用 \(finding.ruleId)")
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .onExitCommand { onDismiss() }
    }
}
