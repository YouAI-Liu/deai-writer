#if DEBUG
import AppKit
import SwiftUI

/// Uses the production views with an in-memory replacement for visual QA.
struct DebugUIShowcase: View {
    @StateObject private var model = SuggestionCardModel(finding: sample, matchedText: "说白了，")
    @StateObject private var settings = AppSettings(userDefaults: UserDefaults(suiteName: "deai.ui-preview")!)
    @State private var page = "建议"
    @State private var reduced = false
    @State private var darkHost = false
    @State private var applications = 0

    private static let sample = Finding(
        category: .aiToneZh, ruleId: "zh.banned_opener", message: "删掉套话，直接说重点。",
        start: 0, end: 4, suggestions: [""], tier: 1
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                ForEach(["建议", "设置", "权限", "规则窗口", "下划线"], id: \.self) { title in
                    Button(title) { page = title }.buttonStyle(.plain)
                        .foregroundStyle(page == title ? DeAIDesign.text : DeAIDesign.muted)
                }
                Spacer()
            }
            .font(DeAIDesign.font(12, weight: .medium)).padding(20)
            Divider()
            Group {
                switch page {
                case "设置": SettingsView(settings: settings, currentBundleId: "com.apple.TextEdit")
                case "权限": PermissionView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case "规则窗口": ContentView()
                case "下划线": DebugUnderlineColors()
                default: cardStage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 790)
        .background(DeAIDesign.background)
        .onAppear {
            model.onApply = { _, completion in
                applications += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { completion(true) }
            }
            model.onDismiss = { model.visible = false }
            model.onIgnore = { model.visible = false }
            model.onDisableRule = { model.visible = false }
        }
    }

    private var cardStage: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZStack(alignment: .top) {
                SuggestionCardView(model: model, autoDismiss: false)
                    .environment(\.deaiReducedMotionOverride, reduced ? true : nil)
                    .padding(.top, 64)
            }
            .frame(maxWidth: .infinity).frame(height: 410)
            .background(darkHost ? DeAIDesign.sidebar : DeAIDesign.background)
            HStack(spacing: 12) {
                Button("待处理") { reset() }
                Button("应用中") { reset(); model.phase = .loading }
                Button("改写结果") { reset(); model.phase = .diff("") }
                Button("成功") { reset(); model.phase = .success }
                Button("长文本") {
                    let text = String(repeating: "长文本，", count: 400)
                    model.update(
                        finding: Finding(category: .markdown, ruleId: "md.bold", message: "Markdown 残留：加粗",
                                         start: 0, end: UInt32(text.utf16.count + 4), suggestions: [text], tier: 1),
                        matchedText: "**" + text + "**"
                    )
                }
            }
            .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
            HStack {
                Toggle("减少动态效果", isOn: $reduced)
                Toggle("深色宿主", isOn: $darkHost)
            }
            .toggleStyle(DeAIToggleStyle()).font(DeAIDesign.font(12))
            Text("替换调用：\(applications)").font(DeAIDesign.font(11)).foregroundStyle(DeAIDesign.muted)
            Spacer()
        }
        .padding(30)
    }

    private func reset() {
        model.update(finding: Self.sample, matchedText: "说白了，")
        model.visible = true
    }
}

/// The per-kind check chips in both states, and again as rendered inside a
/// disabled app group (the `isEnabled` path of DeAIChipToggleStyle).
private struct DebugChipRows: View {
    var disabled = false
    @Environment(\.deaiUILanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(disabled ? "组已停用" : "组已启用")
                .font(DeAIDesign.font(10))
                .foregroundStyle(DeAIDesign.muted)
            HStack(spacing: 8) {
                ForEach(CheckKind.allCases, id: \.self) { kind in
                    Toggle(kind.shortName(lang), isOn: .constant(true))
                        .toggleStyle(DeAIChipToggleStyle())
                }
            }
            HStack(spacing: 8) {
                ForEach(CheckKind.allCases, id: \.self) { kind in
                    Toggle(kind.shortName(lang), isOn: .constant(false))
                        .toggleStyle(DeAIChipToggleStyle())
                }
            }
        }
        .font(DeAIDesign.font(11))
        .disabled(disabled)
    }
}

private struct DebugUnderlineColors: View {
    private let samples: [(Category, String)] = [
        (.grammar, "语法"), (.aiToneZh, "中文 AI 腔"),
        (.aiToneEn, "英文 AI 腔"), (.markdown, "Markdown"),
        (.personal, "个人偏好")
    ]

    var body: some View {
        HStack(spacing: 0) {
            column(dark: false)
            column(dark: true)
        }
        .frame(width: 620, height: 400)
    }

    private func column(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(dark ? "深色背景" : "浅色背景")
                .font(DeAIDesign.font(16, weight: .medium))
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                VStack(alignment: .leading, spacing: 3) {
                    Text(sample.1).font(DeAIDesign.font(13))
                    DebugUnderlineSample(category: sample.0, dark: dark).frame(width: 240, height: 10)
                }
            }
        }
        .padding(30).frame(width: 310, height: 400, alignment: .topLeading)
        .foregroundStyle(DeAIDesign.text)
        .background(DeAIDesign.background)
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

private struct DebugUnderlineSample: NSViewRepresentable {
    let category: Category
    let dark: Bool

    func makeNSView(context: Context) -> UnderlineView {
        UnderlineView(frame: .zero)
    }

    func updateNSView(_ view: UnderlineView, context: Context) {
        view.previewAppearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.render([
            PositionedFinding(
                finding: Finding(category: category, ruleId: "", message: "", start: 0, end: 1,
                                 suggestions: [], tier: 1),
                rects: [CGRect(x: 0, y: 5, width: 240, height: 1)]
            )
        ])
    }
}

final class DebugUIWindow {
    private static var window: NSWindow?

    static func open() {
        let host = NSHostingView(rootView: DebugUIShowcase())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 790),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "DeAI Debug — UI 预览"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
#endif

#if DEBUG
/// AppKit snapshots of the running SwiftUI views, without host-app permissions.
@MainActor
final class DebugUICapture {
    private static var active: DebugUICapture?
    private let directory: URL
    private let window: NSWindow
    private let model = SuggestionCardModel(
        finding: Finding(category: .markdown, ruleId: "md.bold", message: "Markdown 残留：加粗",
                         start: 0, end: 6, suggestions: ["粗体"], tier: 1),
        matchedText: "**粗体**"
    )
    private let controller = AppController()

    private init(directory: String) {
        self.directory = URL(fileURLWithPath: directory, isDirectory: true)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "DeAI Debug — 截图"
        window.isReleasedWhenClosed = false
    }

    static func start(directory: String) {
        let capture = DebugUICapture(directory: directory)
        active = capture
        Task { await capture.run() }
    }

    private func show<V: View>(_ view: V, size: NSSize, dark: Bool = false) {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func card(dark: Bool = false, reduced: Bool = false) -> some View {
        SuggestionCardView(model: model, autoDismiss: false)
            .environment(\.deaiReducedMotionOverride, reduced ? true : nil)
            .padding(.top, 74)
            .frame(width: 620, height: 500)
            .background(DeAIDesign.background)
    }

    private func save(_ name: String, after delay: Double = 0.6) async throws {
        FileHandle.standardError.write(Data("CAP save \(name)\n".utf8))
        try await Task.sleep(for: .seconds(delay))
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        print("UI screenshot: \(name)")
    }

    /// Stage for the rewrite panel — the view adapts to the stage's
    /// colorScheme environment like the card. The real panel refits to
    /// content; the fixed stage must be tall enough or the result-phase
    /// ScrollViews collapse to zero (expanded 记住改法 needs ~560).
    private func rewriteStage(
        _ model: RewritePanelModel, dark: Bool = false, height: CGFloat = 420
    ) -> some View {
        RewritePanelView(model: model)
            .padding(60)
            .frame(width: 620, height: height)
            .background(DeAIDesign.background)
    }

    private func scrollToBottom(in view: NSView?) {
        scrollTo(fraction: 1, in: view)
    }

    private func scrollTo(fraction: CGFloat, in view: NSView?) {
        guard let view else { return }
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            let visible = scroll.contentView.bounds.height
            let top = document.isFlipped
                ? (document.bounds.height - visible) * fraction
                : document.bounds.height * fraction
            document.scroll(NSPoint(x: 0, y: max(0, top)))
            return
        }
        for child in view.subviews { scrollTo(fraction: fraction, in: child) }
    }

    private func run() async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            model.onDismiss = {}
            model.onApply = { _, completion in completion(true) }
            show(card(), size: NSSize(width: 620, height: 500))
            try await save("card-idle")
            model.update(
                finding: Finding(
                    category: .aiToneZh, ruleId: "zh.banned_opener",
                    message: "删掉套话，直接说重点。", start: 0, end: 4,
                    suggestions: [""], tier: 1
                ),
                matchedText: "说白了，"
            )
            try await save("card-deletion")
            model.update(
                finding: Finding(
                    category: .grammar, ruleId: "harper.Agreement",
                    message: "主谓不一致", start: 0, end: 2,
                    suggestions: ["goes", "went"], tier: 1
                ),
                matchedText: "go"
            )
            try await save("card-multi")
            model.update(
                finding: Finding(
                    category: .markdown, ruleId: "md.bold",
                    message: "Markdown 残留：加粗", start: 0, end: 6,
                    suggestions: ["粗体"], tier: 1
                ),
                matchedText: "**粗体**"
            )
            model.phase = .loading
            try await save("card-loading")
            model.update(finding: model.finding, matchedText: model.matchedText)
            model.apply("粗体")
            model.apply("粗体")
            try await save("card-success-animation", after: 0.38)
            try await save("card-success")
            model.update(finding: model.finding, matchedText: model.matchedText)
            model.phase = .diff("改写后的直接表述。")
            try await save("card-diff-structure")
            model.update(finding: model.finding, matchedText: model.matchedText)
            show(card(dark: true), size: NSSize(width: 620, height: 500))
            try await save("card-dark-host")
            show(card(reduced: true), size: NSSize(width: 620, height: 500))
            try await save("card-reduced-motion")
            model.phase = .success
            try await save("card-reduced-success")
            model.update(
                finding: Finding(category: .markdown, ruleId: "md.bold", message: "Markdown 残留：加粗",
                                 start: 0, end: 1604, suggestions: [String(repeating: "长文本，", count: 400)], tier: 1),
                matchedText: "**" + String(repeating: "长文本，", count: 400) + "**"
            )
            show(card(), size: NSSize(width: 620, height: 600))
            try await save("card-long-text")
            try await save("card-long-text-bottom")
            show(DebugUnderlineColors(), size: NSSize(width: 620, height: 400))
            try await save("underline-colors")
            show(SettingsView(settings: controller.settings, currentBundleId: "com.apple.TextEdit"),
                 size: NSSize(width: 560, height: 660))
            try await save("settings")
            // same zh Check tab, named for the language-row regression check
            try await save("settings-check")
            scrollToBottom(in: window.contentView)
            try await save("settings-rules")
            // 应用类型 section mid-scroll: the browser group is disabled by
            // default, showing the dimmed chip style; the hard-excluded
            // .sensitive group no longer appears at all
            show(SettingsView(settings: controller.settings, currentBundleId: "com.apple.TextEdit"),
                 size: NSSize(width: 560, height: 660))
            scrollTo(fraction: 0.42, in: window.contentView)
            try await save("settings-groups")
            scrollToBottom(in: window.contentView)
            show(SettingsView(settings: controller.settings, currentBundleId: "com.apple.TextEdit", initialTab: 1),
                 size: NSSize(width: 560, height: 660))
            try await save("settings-appearance")
            show(SettingsView(settings: controller.settings, currentBundleId: "com.apple.TextEdit", initialTab: 2),
                 size: NSSize(width: 560, height: 660))
            try await save("settings-ai")
            show(SettingsView(settings: controller.settings, currentBundleId: "com.apple.TextEdit",
                              initialTab: 2, hotkeyRecordingPreview: true),
                 size: NSSize(width: 560, height: 660))
            try await save("settings-ai-recording")
            // 个人 tab with sample entries — a temp-dir store so the real
            // ~/Library/Application Support/DeAI files stay untouched
            let captureLexicon = PersonalLexiconStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("deai-capture-lexicon",
                                            isDirectory: true)
            )
            _ = captureLexicon.addEntry(
                kind: .replace, term: "赋能", replacement: "帮助"
            )
            _ = captureLexicon.addEntry(kind: .avoid, term: "说白了")
            _ = captureLexicon.addEntry(kind: .keep, term: "保留词")
            _ = captureLexicon.addEntry(
                kind: .replace, term: "delve", replacement: "dig into",
                match: .caseInsensitive
            )
            _ = captureLexicon.addEntry(
                kind: .avoid, term: "tapestry", match: .wholeWord
            )
            // skills fixture: a temp-dir store with a realistic 25k-char
            // skill so the 较长 warning badge shows
            let skillsDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("deai-capture-skills-\(UUID().uuidString)",
                                        isDirectory: true)
            let captureSkills = RewriteSkillStore(
                directory: skillsDir.appendingPathComponent("skills",
                                                            isDirectory: true),
                legacyStyleFile: skillsDir.appendingPathComponent("style.md")
            )
            _ = captureSkills.save(
                RewriteSkill(
                    id: "long-skill", name: "长技能示例",
                    description: "", language: .any,
                    body: String(repeating: "中文改写指导内容。", count: 3125),
                    isBuiltin: false
                )
            )
            _ = captureSkills.save(
                RewriteSkill(
                    id: "en-skill", name: "English only",
                    description: "", language: .en,
                    body: "Rewrite in a direct, plain style.",
                    isBuiltin: false
                )
            )
            let captureSettings = AppSettings(
                userDefaults: UserDefaults(suiteName: "deai.capture-personal")!,
                secrets: InMemorySecretStore(),
                lexicon: captureLexicon,
                skills: captureSkills
            )
            // pin zh — a fresh suite would follow the machine's locale
            captureSettings.uiLanguage = .zh
            show(SettingsView(settings: captureSettings, initialTab: 3),
                 size: NSSize(width: 560, height: 660))
            try await save("settings-personal")
            scrollToBottom(in: window.contentView)
            try await save("settings-personal-scroll")
            // AI tab scrolled to the skills section (25k warn badge)
            show(SettingsView(settings: captureSettings, initialTab: 2),
                 size: NSSize(width: 560, height: 660))
            scrollTo(fraction: 0.55, in: window.contentView)
            try await save("settings-ai-skills")
            scrollToBottom(in: window.contentView)
            try await save("settings-ai-skills-list")
            // skill edit sheet (user skill, editable)
            if let longSkill = captureSkills.skills.first(where: {
                $0.id == "long-skill"
            }) {
                show(SkillEditSheet(skill: longSkill, store: captureSkills),
                     size: NSSize(width: 520, height: 480))
                try await save("skill-sheet")
                show(SkillEditSheet(skill: longSkill, store: captureSkills),
                     size: NSSize(width: 520, height: 480), dark: true)
                try await save("skill-sheet-dark")
            }
            // built-in sheet: read-only + 复制为新技能
            if let builtin = captureSkills.skills.first {
                for lang in [UILanguage.zh, .en] {
                    for dark in [false, true] {
                        show(SkillEditSheet(skill: builtin, store: captureSkills)
                                .environment(\.deaiUILanguage, lang),
                             size: NSSize(width: 520, height: 480), dark: dark)
                        try await save("skill-sheet-builtin-\(lang.rawValue)-\(dark ? "dark" : "light")")
                    }
                }
            }
            // rewrite panel states (mock model — same view the panel hosts)
            let rewriteModel = RewritePanelModel()
            rewriteModel.phase = .loading
            rewriteModel.original = "说白了，这一段开头太套话。"
            show(rewriteStage(rewriteModel), size: NSSize(width: 620, height: 420))
            try await save("rewrite-loading")
            rewriteModel.phase = .result
            rewriteModel.result = "这一段开头直接说重点。"
            try await save("rewrite-result")
            // 记住改法 expanded: checkbox list of word-level changed pairs
            rewriteModel.rememberPairs = RewriteDiff.wordPairs(
                original: rewriteModel.original,
                result: rewriteModel.result
            )
            rewriteModel.rememberChecked = Set(rewriteModel.rememberPairs.indices)
            rewriteModel.rememberExpanded = true
            show(rewriteStage(rewriteModel, height: 560),
                 size: NSSize(width: 620, height: 560))
            try await save("rewrite-remember")
            rewriteModel.rememberExpanded = false
            rewriteModel.rememberPairs = []
            rewriteModel.rememberChecked = []
            rewriteModel.phase = .noChange
            try await save("rewrite-nochange")
            // changed text with no splittable pairs → muted note instead
            // of an empty 记住改法 section
            rewriteModel.phase = .result
            rewriteModel.rememberPairs = []
            rewriteModel.rememberChecked = []
            try await save("rewrite-note")
            show(PermissionView(), size: NSSize(width: 420, height: 360))
            try await save("permission")
            show(MenuContent(controller: controller), size: NSSize(width: 300, height: 270))
            try await save("menu")
            show(MenuContent(controller: controller, groupsExpanded: true),
                 size: NSSize(width: 300, height: 400))
            try await save("menu-expanded")
            show(ContentView(), size: NSSize(width: 700, height: 620))
            try await save("rule-window", after: 0.6)
            show(SettingsView(settings: controller.settings, currentBundleId: "com.apple.TextEdit"),
                 size: NSSize(width: 560, height: 660), dark: true)
            try await save("settings-dark")
            show(SettingsView(settings: controller.settings, currentBundleId: "com.apple.TextEdit", initialTab: 1),
                 size: NSSize(width: 560, height: 660), dark: true)
            try await save("settings-appearance-dark")
            show(SettingsView(settings: controller.settings, currentBundleId: "com.apple.TextEdit", initialTab: 2),
                 size: NSSize(width: 560, height: 660), dark: true)
            try await save("settings-ai-dark")
            show(SettingsView(settings: captureSettings, initialTab: 2),
                 size: NSSize(width: 560, height: 660), dark: true)
            scrollTo(fraction: 0.55, in: window.contentView)
            try await save("settings-ai-skills-dark")
            scrollToBottom(in: window.contentView)
            try await save("settings-ai-skills-list-dark")
            show(SettingsView(settings: controller.settings, currentBundleId: "com.apple.TextEdit",
                              initialTab: 2, hotkeyRecordingPreview: true),
                 size: NSSize(width: 560, height: 660), dark: true)
            try await save("settings-ai-recording-dark")
            show(SettingsView(settings: captureSettings, initialTab: 3),
                 size: NSSize(width: 560, height: 660), dark: true)
            try await save("settings-personal-dark")
            show(SettingsView(settings: controller.settings, currentBundleId: "com.apple.TextEdit"),
                 size: NSSize(width: 560, height: 660), dark: true)
            scrollTo(fraction: 0.42, in: window.contentView)
            try await save("settings-groups-dark")
            // chip contrast check: both on/off chip states, group on vs off
            show(DebugChipRows().padding(24).background(DeAIDesign.background),
                 size: NSSize(width: 360, height: 140))
            try await save("settings-chips")
            show(DebugChipRows(disabled: true).padding(24).background(DeAIDesign.background),
                 size: NSSize(width: 360, height: 140))
            try await save("settings-chips-disabled")
            show(DebugChipRows().padding(24).background(DeAIDesign.background),
                 size: NSSize(width: 360, height: 140), dark: true)
            try await save("settings-chips-dark")
            show(DebugChipRows(disabled: true).padding(24).background(DeAIDesign.background),
                 size: NSSize(width: 360, height: 140), dark: true)
            try await save("settings-chips-disabled-dark")
            rewriteModel.phase = .result
            rewriteModel.rememberPairs = RewriteDiff.wordPairs(
                original: rewriteModel.original,
                result: rewriteModel.result
            )
            rewriteModel.rememberChecked = Set(rewriteModel.rememberPairs.indices)
            rewriteModel.rememberExpanded = true
            show(rewriteStage(rewriteModel, dark: true, height: 560),
                 size: NSSize(width: 620, height: 560), dark: true)
            try await save("rewrite-remember-dark")
            rewriteModel.rememberExpanded = false
            rewriteModel.rememberPairs = []
            rewriteModel.rememberChecked = []
            try await save("rewrite-result-dark")
            show(PermissionView(), size: NSSize(width: 420, height: 360), dark: true)
            try await save("permission-dark")
            show(ContentView(), size: NSSize(width: 700, height: 620), dark: true)
            try await save("rule-window-dark")
            model.update(
                finding: Finding(category: .markdown, ruleId: "md.bold", message: "Markdown 残留：加粗",
                                 start: 0, end: 6, suggestions: ["粗体"], tier: 1),
                matchedText: "**粗体**"
            )
            show(card(dark: true), size: NSSize(width: 620, height: 500), dark: true)
            try await save("card-dark-mode")
            model.phase = .success
            try await save("card-success-dark")
            // selection-check session card: "2/3" stepper in the header
            model.update(finding: model.finding, matchedText: model.matchedText)
            model.setSessionStep(index: 1, count: 3)
            try await save("card-session-dark")
            // selection-check empty variant: slider + 重新检测
            model.presentEmpty(sensitivity: 2, flash: false)
            try await save("card-empty-dark")
            model.update(finding: model.finding, matchedText: model.matchedText)
            show(card(), size: NSSize(width: 620, height: 500))
            model.setSessionStep(index: 1, count: 3)
            try await save("card-session")
            model.presentEmpty(sensitivity: 2, flash: false)
            try await save("card-empty")
            model.presentEmpty(sensitivity: 3, flash: true)
            try await save("card-empty-flash")
            // personal finding: 个人偏好 tag + teal category dot
            model.presentEmpty(sensitivity: 2, flash: false)
            model.update(
                finding: Finding(
                    category: .personal, ruleId: "personal.replace",
                    message: "个人偏好：用「帮助」代替「赋能」",
                    start: 0, end: 2, suggestions: ["帮助"], tier: 1
                ),
                matchedText: "赋能"
            )
            try await save("card-personal")
            show(card(dark: true), size: NSSize(width: 620, height: 500), dark: true)
            try await save("card-personal-dark")
            model.setSessionStep(index: 0, count: 0)
            show(MenuContent(controller: controller), size: NSSize(width: 300, height: 270), dark: true)
            try await save("menu-dark")
            show(MenuContent(controller: controller, groupsExpanded: true),
                 size: NSSize(width: 300, height: 400), dark: true)
            try await save("menu-expanded-dark")

            // ---- English UI (uiLanguage = .en on a temp-suite settings
            // object — the real com.local.deai defaults stay untouched) ----
            let enSettings = AppSettings(
                userDefaults: UserDefaults(suiteName: "deai.capture-en")!,
                secrets: InMemorySecretStore(),
                lexicon: captureLexicon,
                skills: captureSkills
            )
            enSettings.uiLanguage = .en
            show(
                SkillsSectionView(settings: enSettings, store: captureSkills,
                                  editingSkill: .constant(nil), safetyExpanded: true)
                    .environment(\.deaiUILanguage, .en)
                    .padding(30).background(DeAIDesign.background),
                size: NSSize(width: 560, height: 660)
            )
            try await save("settings-safety-expanded-en")
            let go = enSettings.addProvider(preset: .opencodeGo)
            enSettings.activeProviderId = go.id
            show(SettingsView(settings: enSettings, initialTab: 2),
                 size: NSSize(width: 560, height: 660), dark: true)
            scrollTo(fraction: 0.15, in: window.contentView)
            try await save("settings-provider-dark")
            var customGo = go
            customGo.model = "my-custom-model"
            enSettings.updateProvider(customGo)
            show(SettingsView(settings: enSettings, initialTab: 2),
                 size: NSSize(width: 560, height: 660), dark: true)
            scrollTo(fraction: 0.15, in: window.contentView)
            try await save("settings-provider-dark-custom")
            enSettings.deleteProvider(id: go.id)
            show(SettingsView(settings: enSettings, currentBundleId: "com.apple.TextEdit"),
                 size: NSSize(width: 560, height: 660))
            try await save("settings-check-en")
            show(SettingsView(settings: enSettings, currentBundleId: "com.apple.TextEdit"),
                 size: NSSize(width: 560, height: 660), dark: true)
            try await save("settings-check-en-dark")
            show(SettingsView(settings: enSettings, initialTab: 1),
                 size: NSSize(width: 560, height: 660))
            try await save("settings-appearance-en")
            show(SettingsView(settings: enSettings, initialTab: 2),
                 size: NSSize(width: 560, height: 660))
            try await save("settings-ai-en")
            show(SettingsView(settings: enSettings, initialTab: 2),
                 size: NSSize(width: 560, height: 660), dark: true)
            try await save("settings-ai-en-dark")
            // skills section in English (scrolled to it)
            show(SettingsView(settings: enSettings, initialTab: 2),
                 size: NSSize(width: 560, height: 660))
            scrollTo(fraction: 0.55, in: window.contentView)
            try await save("settings-ai-skills-en")
            scrollToBottom(in: window.contentView)
            try await save("settings-ai-skills-list-en")
            if let longSkillEn = captureSkills.skills.first(where: {
                $0.id == "long-skill"
            }) {
                show(
                    SkillEditSheet(skill: longSkillEn, store: captureSkills)
                        .environment(\.deaiUILanguage, .en),
                    size: NSSize(width: 520, height: 480)
                )
                try await save("skill-sheet-en")
            }
            show(SettingsView(settings: enSettings, initialTab: 3),
                 size: NSSize(width: 560, height: 660))
            try await save("settings-personal-en")
            show(SettingsView(settings: enSettings, initialTab: 3),
                 size: NSSize(width: 560, height: 660), dark: true)
            try await save("settings-personal-en-dark")

            model.lang = .en
            model.update(
                finding: Finding(category: .markdown, ruleId: "md.bold",
                                 message: "Markdown 残留：加粗", start: 0, end: 6,
                                 suggestions: ["粗体"], tier: 1),
                matchedText: "**粗体**"
            )
            show(card(), size: NSSize(width: 620, height: 500))
            try await save("card-idle-en")
            model.setSessionStep(index: 1, count: 3)
            try await save("card-session-en")
            model.presentEmpty(sensitivity: 2, flash: false)
            try await save("card-empty-en")
            show(card(dark: true), size: NSSize(width: 620, height: 500), dark: true)
            model.setSessionStep(index: 1, count: 3)
            try await save("card-session-en-dark")
            model.presentEmpty(sensitivity: 2, flash: false)
            try await save("card-empty-en-dark")
            model.setSessionStep(index: 0, count: 0)

            rewriteModel.lang = .en
            rewriteModel.phase = .result
            rewriteModel.original = "It is worth noting that we need to leverage synergies and delve into this. "
                + String(repeating: "The team will review the findings, document the changes, and complete the next round of testing. ", count: 8)
                + "This is the final sentence of the original."
            rewriteModel.result = String(repeating: "The team will review the findings and test the changes. ", count: 12)
                + "This is the final sentence of the rewrite."
            rewriteModel.rememberPairs = []
            rewriteModel.rememberExpanded = false
            show(rewriteStage(rewriteModel, height: 660),
                 size: NSSize(width: 620, height: 660))
            try await save("rewrite-long-en")
            scrollToBottom(in: window.contentView)
            try await save("rewrite-long-en-bottom")
            rewriteModel.original = "It is worth noting that we need to leverage synergies and delve into this."
            rewriteModel.result = "The team will review this together."
            show(rewriteStage(rewriteModel), size: NSSize(width: 620, height: 420))
            try await save("rewrite-qa-en")
            rewriteModel.rememberPairs = RewriteDiff.wordPairs(
                original: rewriteModel.original,
                result: rewriteModel.result
            )
            rewriteModel.rememberChecked = Set(rewriteModel.rememberPairs.indices)
            rewriteModel.rememberExpanded = true
            show(rewriteStage(rewriteModel, height: 560),
                 size: NSSize(width: 620, height: 560))
            try await save("rewrite-remember-en")
            show(rewriteStage(rewriteModel, dark: true, height: 560),
                 size: NSSize(width: 620, height: 560), dark: true)
            try await save("rewrite-remember-en-dark")
            rewriteModel.rememberExpanded = false
            rewriteModel.rememberPairs = []
            rewriteModel.rememberChecked = []
            show(rewriteStage(rewriteModel), size: NSSize(width: 620, height: 420))
            try await save("rewrite-note-en")

            show(MenuContent(controller: controller, groupsExpanded: true,
                             settings: enSettings),
                 size: NSSize(width: 300, height: 400))
            try await save("menu-expanded-en")
            show(MenuContent(controller: controller, groupsExpanded: true,
                             settings: enSettings),
                 size: NSSize(width: 300, height: 400), dark: true)
            try await save("menu-expanded-en-dark")
            show(PermissionView().environment(\.deaiUILanguage, .en),
                 size: NSSize(width: 420, height: 360))
            try await save("permission-en")
            print("UI capture complete")
        } catch {
            FileHandle.standardError.write(
                Data("UI capture failed: \(error)\n".utf8)
            )
            print("UI capture failed: \(error)")
        }
        FileHandle.standardError.write(Data("CAP end\n".utf8))
        NSApp.terminate(nil)
    }
}
#endif
