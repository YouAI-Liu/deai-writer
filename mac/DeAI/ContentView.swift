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
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("规则测试")
                    .font(DeAIDesign.font(26, weight: .semibold)).tracking(-0.8)
                Spacer()
                Text("\(findings.count) 条提示")
                    .font(DeAIDesign.font(11)).foregroundStyle(DeAIDesign.muted)
            }
            TextEditor(text: $text)
                .font(DeAIDesign.font(15)).scrollContentBackground(.hidden)
                .padding(16).frame(minHeight: 140)
                .background(DeAIDesign.surface, in: RoundedRectangle(cornerRadius: DeAIDesign.radius))
            HStack(spacing: 20) {
                Toggle("语法", isOn: $grammar)
                Toggle("英文 AI 腔", isOn: $aiToneEn)
                Toggle("中文 AI 腔", isOn: $aiToneZh)
                Toggle("Markdown", isOn: $markdown)
            }
            .font(DeAIDesign.font(11)).toggleStyle(DeAIToggleStyle())
            HStack {
                SensitivityControl(selection: $sensitivity).frame(width: 230)
                Spacer()
                Button("清除 Markdown") {
                    text = stripMarkdown(text: text, opts: currentOptions())
                }
                .buttonStyle(DeAIButtonStyle())
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(findings, id: \.self) { finding in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SecondaryLabel(categoryName(finding.category))
                                Spacer()
                                SecondaryLabel(finding.ruleId)
                            }
                            Text(finding.message).font(DeAIDesign.font(14, weight: .medium))
                            Text("原文：\(excerpt(finding))")
                                .font(DeAIDesign.font(12)).foregroundStyle(DeAIDesign.muted)
                            if !finding.suggestions.isEmpty {
                                Text("建议：\(finding.suggestions.joined(separator: " / "))")
                                    .font(DeAIDesign.font(12))
                            }
                        }
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DeAIDesign.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
        }
        .padding(30)
        .foregroundStyle(DeAIDesign.text)
        .background(DeAIDesign.canvas)
        .frame(minWidth: 700, minHeight: 620)
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
        case .grammar: "语法"
        case .aiToneEn: "英文 AI 腔"
        case .aiToneZh: "中文 AI 腔"
        case .markdown: "Markdown"
        }
    }
}

#Preview {
    ContentView()
}
