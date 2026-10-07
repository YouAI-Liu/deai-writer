import SwiftUI

struct ContentView: View {
    @State private var text = "我们不是工具，而是伙伴。This is an test. **bold**"
    @State private var grammar = true
    @State private var aiToneEn = true
    @State private var aiToneZh = true
    @State private var markdown = true
    @State private var sensitivity = 2
    @State private var findings: [Finding] = []

    private let checker = Checker()
    private let queue = DispatchQueue(label: "com.local.deai.check", qos: .userInitiated)
    @State private var pending: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 140)
            HStack {
                Toggle("Grammar", isOn: $grammar)
                Toggle("AI tone EN", isOn: $aiToneEn)
                Toggle("AI tone 中文", isOn: $aiToneZh)
                Toggle("Markdown", isOn: $markdown)
            }
            HStack {
                Picker("敏感度", selection: $sensitivity) {
                    Text("严格").tag(1)
                    Text("标准").tag(2)
                    Text("敏感").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                Spacer()
                Button("清除 Markdown") {
                    text = stripMarkdown(text: text, opts: currentOptions())
                }
            }
            List(findings, id: \.self) { finding in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(categoryName(finding.category))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(finding.ruleId)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("tier \(finding.tier)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("[\(finding.start), \(finding.end)) “\(excerpt(finding))”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(finding.message)
                    if !finding.suggestions.isEmpty {
                        Text("Suggestions: \(finding.suggestions.joined(separator: ", "))")
                            .font(.callout)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
        .onAppear(perform: schedule)
        .onChange(of: text) { _, _ in schedule() }
        .onChange(of: grammar) { _, _ in schedule() }
        .onChange(of: aiToneEn) { _, _ in schedule() }
        .onChange(of: aiToneZh) { _, _ in schedule() }
        .onChange(of: markdown) { _, _ in schedule() }
        .onChange(of: sensitivity) { _, _ in schedule() }
    }

    private func currentOptions() -> CheckOptions {
        CheckOptions(
            grammar: grammar,
            aiToneEn: aiToneEn,
            aiToneZh: aiToneZh,
            markdown: markdown,
            sensitivity: UInt8(clamping: sensitivity)
        )
    }

    /// 300ms debounce; the check itself runs off the main thread.
    private func schedule() {
        pending?.cancel()
        let snapshot = text
        let opts = currentOptions()
        let item = DispatchWorkItem { [checker] in
            let result = checker.check(text: snapshot, opts: opts)
            DispatchQueue.main.async {
                findings = result
            }
        }
        pending = item
        queue.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    /// `[start, end)` is a UTF-16 code unit range — the same unit NSString uses.
    private func excerpt(_ finding: Finding) -> String {
        let ns = text as NSString
        guard finding.start <= finding.end, Int(finding.end) <= ns.length else { return "" }
        return ns.substring(with: NSRange(location: Int(finding.start), length: Int(finding.end - finding.start)))
    }

    private func categoryName(_ category: Category) -> String {
        switch category {
        case .grammar: "Grammar"
        case .aiToneEn: "AI tone (EN)"
        case .aiToneZh: "AI tone (中文)"
        case .markdown: "Markdown"
        }
    }
}

#Preview {
    ContentView()
}
