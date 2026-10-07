import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Frontmost non-DeAI app bundle id (for "add current app").
    var currentBundleId: String?

    var body: some View {
        TabView {
            CheckSettingsTab(settings: settings, currentBundleId: currentBundleId)
                .tabItem { Label("检查", systemImage: "checklist") }
            AISettingsTab(settings: settings)
                .tabItem { Label("AI 改写", systemImage: "wand.and.stars") }
        }
        .frame(width: 560, height: 620)
    }
}

/// The original settings content — unchanged, just moved into a tab.
private struct CheckSettingsTab: View {
    @ObservedObject var settings: AppSettings
    var currentBundleId: String?

    @State private var newBundleId = ""
    @State private var selectedTab: Int

    private static let categories: [Category] = [.grammar, .aiToneZh, .aiToneEn, .markdown]

    init(settings: AppSettings, currentBundleId: String? = nil, initialTab: Int = 0) {
        self.settings = settings
        self.currentBundleId = currentBundleId
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            checksTab
                .tabItem { Label("检查", systemImage: "checkmark.circle") }
                .tag(0)
            underlineTab
                .tabItem { Label("下划线样式", systemImage: "textformat.underline") }
                .tag(1)
            appsTab
                .tabItem { Label("应用", systemImage: "app.badge.checkmark") }
                .tag(2)
        }
        .frame(minWidth: 560, idealWidth: 560, minHeight: 620)
    }

    // MARK: - 检查

    private var checksTab: some View {
        Form {
            Section("检查类别") {
                Toggle("语法 (Grammar)", isOn: $settings.grammar)
                Toggle("中文 AI 腔", isOn: $settings.aiToneZh)
                Toggle("英文 AI 腔", isOn: $settings.aiToneEn)
                Toggle("Markdown 残留", isOn: $settings.markdown)
            }
            Section("敏感度") {
                Picker("敏感度", selection: $settings.sensitivity) {
                    Text("严格").tag(1)
                    Text("标准").tag(2)
                    Text("敏感").tag(3)
                }
                .pickerStyle(.segmented)
            }
            Section("已停用规则") {
                if settings.disabledRuleIds.isEmpty {
                    Text("无").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(settings.disabledRuleIds).sorted(), id: \.self) { id in
                        HStack {
                            Text(id).font(.callout.monospaced())
                            Spacer()
                            Button("重新启用") {
                                settings.disabledRuleIds.remove(id)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 下划线样式

    private var underlineTab: some View {
        Form {
            Section("预览") {
                UnderlinePreview(appearance: settings.underline)
                    .frame(height: 64)
            }
            Section("分类样式") {
                ForEach(Self.categories, id: \.self) { category in
                    HStack {
                        Text(category.displayName)
                        Spacer()
                        ColorPicker(
                            "颜色",
                            selection: colorBinding(for: category),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        Picker("线型", selection: shapeBinding(for: category)) {
                            ForEach(UnderlineShape.allCases, id: \.self) { shape in
                                Text(shape.displayName).tag(shape)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 96)
                    }
                }
            }
            Section("全局") {
                sliderRow("粗细", value: $settings.underline.thickness, range: 0.5...4)
                sliderRow("不透明度", value: $settings.underline.opacity, range: 0.2...1)
                sliderRow("距离", value: $settings.underline.offset, range: -2...4)
                Toggle("低置信度显示为虚线", isOn: $settings.underline.dimLowConfidence)
                Toggle("背景高亮", isOn: $settings.underline.highlightFill)
                HStack {
                    Spacer()
                    Button("恢复默认") {
                        settings.underline = .default
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sliderRow(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>
    ) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text(String(format: "%.1f", value.wrappedValue))
                .font(.callout.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func colorBinding(for category: Category) -> Binding<Color> {
        Binding(
            get: { Color(hex: settings.underline.style(for: category).colorHex) },
            set: { newColor in
                var style = settings.underline.style(for: category)
                style.colorHex = newColor.hexString ?? style.colorHex
                var appearance = settings.underline
                appearance.styles[UnderlineAppearance.key(for: category)] = style
                settings.underline = appearance
            }
        )
    }

    private func shapeBinding(for category: Category) -> Binding<UnderlineShape> {
        Binding(
            get: { settings.underline.style(for: category).shape },
            set: { newShape in
                var style = settings.underline.style(for: category)
                style.shape = newShape
                var appearance = settings.underline
                appearance.styles[UnderlineAppearance.key(for: category)] = style
                settings.underline = appearance
            }
        )
    }

    // MARK: - 应用

    private var appsTab: some View {
        Form {
            Section("应用类型") {
                ForEach(AppGroup.allCases, id: \.self) { group in
                    let rule = settings.groupRules[group]
                        ?? AppGroup.defaultRule(for: group)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(group.displayName)
                                Text(group.examples)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("启用", isOn: groupEnabledBinding(group))
                                .labelsHidden()
                        }
                        HStack(spacing: 14) {
                            ForEach(CheckKind.allCases, id: \.self) { kind in
                                Toggle(
                                    kind.shortName,
                                    isOn: groupCheckBinding(group, kind)
                                )
                                .toggleStyle(.checkbox)
                            }
                        }
                        .disabled(!rule.enabled)
                    }
                }
            }
            Section("单个应用例外") {
                ForEach(settings.sortedAppRules, id: \.key) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.key)
                                .font(.callout.monospaced())
                            Text(
                                (entry.value.enabled
                                    ? (entry.value.markdown ? "启用" : "启用(不含 Markdown)")
                                    : "停用")
                                    + " · \(AppGroup.group(for: entry.key).displayName)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("启用", isOn: binding(for: entry.key, enabled: true))
                            .labelsHidden()
                        Toggle("MD", isOn: binding(for: entry.key, enabled: false))
                            .labelsHidden()
                            .help("Markdown 检查")
                        Button(role: .destructive) {
                            settings.appRules.removeValue(forKey: entry.key)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("bundle id (例如 com.apple.TextEdit)", text: $newBundleId)
                        .textFieldStyle(.roundedBorder)
                    Button("添加") {
                        guard !newBundleId.isEmpty else { return }
                        settings.appRules[newBundleId] =
                            settings.defaultAppRule(for: newBundleId)
                        newBundleId = ""
                    }
                    .disabled(newBundleId.isEmpty)
                    if let cur = currentBundleId, !cur.isEmpty {
                        Button("添加当前应用") {
                            settings.appRules[cur] = settings.defaultAppRule(for: cur)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func groupEnabledBinding(_ group: AppGroup) -> Binding<Bool> {
        Binding(
            get: {
                (settings.groupRules[group] ?? AppGroup.defaultRule(for: group)).enabled
            },
            set: { enabled in
                var rule = settings.groupRules[group] ?? AppGroup.defaultRule(for: group)
                rule.enabled = enabled
                settings.groupRules[group] = rule
            }
        )
    }

    private func groupCheckBinding(_ group: AppGroup, _ kind: CheckKind) -> Binding<Bool> {
        Binding(
            get: {
                (settings.groupRules[group] ?? AppGroup.defaultRule(for: group))
                    .checks.contains(kind)
            },
            set: { on in
                var rule = settings.groupRules[group] ?? AppGroup.defaultRule(for: group)
                if on { rule.checks.insert(kind) } else { rule.checks.remove(kind) }
                settings.groupRules[group] = rule
            }
        )
    }

    private func binding(for bundleId: String, enabled: Bool) -> Binding<Bool> {
        Binding(
            get: {
                let rule = settings.appRules[bundleId]
                    ?? settings.defaultAppRule(for: bundleId)
                return enabled ? rule.enabled : rule.markdown
            },
            set: { v in
                var rule = settings.appRules[bundleId]
                    ?? settings.defaultAppRule(for: bundleId)
                if enabled { rule.enabled = v } else { rule.markdown = v }
                settings.appRules[bundleId] = rule
            }
        )
    }
}

/// Provider management + hotkey for the AI rewrite feature.
private struct AISettingsTab: View {
    @ObservedObject var settings: AppSettings

    /// API key draft — the saved key is never echoed back into the field.
    @State private var keyDraft = ""
    @State private var keySaved = false
    /// OpenCode Go only: true when the model isn't one of the known ids.
    @State private var customModel = false
    @State private var testing = false
    @State private var testStatus: String?

    var body: some View {
        Form {
            Section("服务") {
                ForEach(settings.providers) { p in
                    HStack {
                        Image(
                            systemName: p.id == settings.activeProviderId
                                ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(p.name).font(.callout)
                            Text(p.model.isEmpty ? p.preset.label : p.model)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            settings.deleteProvider(id: p.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settings.activeProviderId = p.id
                    }
                }
                Menu("添加服务…") {
                    ForEach(ProviderPreset.allCases, id: \.self) { preset in
                        Button(preset.label) {
                            _ = settings.addProvider(preset: preset)
                        }
                    }
                }
            }
            if let provider = settings.activeProvider {
                providerEditor(provider)
            }
            Section("快捷键") {
                Picker("AI 改写快捷键", selection: $settings.rewriteHotkey) {
                    ForEach(RewriteHotkey.allCases, id: \.self) { h in
                        Text(h.label).tag(h)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshKeyState() }
        .onChange(of: settings.activeProviderId) { _ in refreshKeyState() }
    }

    @ViewBuilder
    private func providerEditor(_ p: ProviderConfig) -> some View {
        Section("配置 — \(p.name)") {
            HStack {
                Text("名称")
                Spacer()
                TextField("名称", text: providerBinding(p.id, \.name))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            }
            HStack {
                Text("接口格式")
                Spacer()
                Picker(
                    "接口格式",
                    selection: providerBinding(
                        p.id, \.format, fallback: .openAIChat
                    )
                ) {
                    ForEach(APIFormat.allCases, id: \.self) { f in
                        Text(f.label).tag(f)
                    }
                }
                .labelsHidden()
                .frame(width: 280)
                // OpenCode Go derives the format from the chosen model
                .disabled(p.preset == .opencodeGo && !customModel)
            }
            HStack {
                Text("Base URL")
                Spacer()
                TextField("https://…", text: providerBinding(p.id, \.baseURL))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            }
            if p.preset == .opencodeGo {
                modelPicker(p)
            } else {
                HStack {
                    Text("模型")
                    Spacer()
                    TextField("模型 id", text: providerBinding(p.id, \.model))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }
            }
            HStack {
                Text("API Key")
                Spacer()
                SecureField(
                    "API Key", text: $keyDraft,
                    onCommit: saveKey
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                Button("保存") { saveKey() }
                    .disabled(keyDraft.isEmpty && !keySaved)
                Text(keySaved ? "已保存 ✓" : "未设置")
                    .font(.caption)
                    .foregroundStyle(keySaved ? .green : .secondary)
            }
            HStack {
                Button(testing ? "测试中…" : "测试连接") { testConnection(p) }
                    .disabled(testing)
                if let testStatus {
                    Text(testStatus)
                        .font(.caption)
                        .foregroundStyle(
                            testStatus.hasPrefix("✓") ? .green : .red
                        )
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private func modelPicker(_ p: ProviderConfig) -> some View {
        HStack {
            Text("模型")
            Spacer()
            Picker("模型", selection: modelSelection(p)) {
                ForEach(OpenCodeGoModels.all, id: \.self) { m in
                    Text(m).tag(m)
                }
                Text("自定义…").tag("__custom__")
            }
            .labelsHidden()
            .frame(width: 280)
        }
        if customModel {
            HStack {
                Text("自定义模型")
                Spacer()
                TextField("模型 id", text: providerBinding(p.id, \.model))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            }
        }
    }

    /// Known model id → its tag; anything else → the 自定义 entry.
    private func modelSelection(_ p: ProviderConfig) -> Binding<String> {
        Binding(
            get: {
                customModel
                    ? "__custom__"
                    : (OpenCodeGoModels.format(for: p.model) != nil
                        ? p.model : "__custom__")
            },
            set: { value in
                guard var cur = settings.providers
                    .first(where: { $0.id == p.id }) else { return }
                if value == "__custom__" {
                    customModel = true
                } else {
                    customModel = false
                    cur.model = value
                    cur.syncFormatWithModel()
                    settings.updateProvider(cur)
                }
            }
        )
    }

    private func providerBinding<T: Hashable>(
        _ id: UUID,
        _ keyPath: WritableKeyPath<ProviderConfig, T>,
        fallback: T
    ) -> Binding<T> {
        Binding(
            get: {
                settings.providers.first(where: { $0.id == id })?[keyPath: keyPath]
                    ?? fallback
            },
            set: { v in
                guard var p = settings.providers
                    .first(where: { $0.id == id }) else { return }
                p[keyPath: keyPath] = v
                p.syncFormatWithModel()
                settings.updateProvider(p)
            }
        )
    }

    private func providerBinding(
        _ id: UUID, _ keyPath: WritableKeyPath<ProviderConfig, String>
    ) -> Binding<String> {
        providerBinding(id, keyPath, fallback: "")
    }

    private func refreshKeyState() {
        keyDraft = ""
        testStatus = nil
        if let id = settings.activeProvider?.id {
            keySaved = settings.secrets.get(id.uuidString) != nil
        } else {
            keySaved = false
        }
        customModel = settings.activeProvider.map {
            $0.preset == .opencodeGo
                && OpenCodeGoModels.format(for: $0.model) == nil
        } ?? false
    }

    private func saveKey() {
        guard let id = settings.activeProvider?.id else { return }
        settings.secrets.set(
            keyDraft.isEmpty ? nil : keyDraft,
            for: id.uuidString
        )
        keyDraft = ""
        keySaved = settings.secrets.get(id.uuidString) != nil
    }

    private func testConnection(_ p: ProviderConfig) {
        testing = true
        testStatus = nil
        let key = settings.secrets.get(p.id.uuidString)
        Task { @MainActor in
            let t0 = CFAbsoluteTimeGetCurrent()
            do {
                _ = try await LLMClient().complete(
                    config: p,
                    apiKey: key,
                    system: RewritePrompt.pingSystem,
                    user: RewritePrompt.pingUser
                )
                let ms = Int(
                    (CFAbsoluteTimeGetCurrent() - t0) * 1000
                )
                testStatus = "✓ 连接成功 (\(ms) ms)"
            } catch {
                testStatus = error.localizedDescription
            }
            testing = false
        }
    }
}

// MARK: - live preview

/// Layer-backed preview that reuses `UnderlineDrawing` so the preview can
/// never drift from the real overlay. Line 1 shows every category's
/// underline under a segment of the sample text; line 2 uses a tier-3
/// (低置信度) finding so the 虚线/highlight toggles are visible.
private final class UnderlinePreviewNSView: NSView {
    var underlineAppearance: UnderlineAppearance = .default {
        didSet { refresh() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        refresh()
    }

    private func refresh() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let font = NSFont.systemFont(ofSize: 14)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        let categories: [Category] = [.grammar, .aiToneZh, .aiToneEn, .markdown]
        let lines: [(text: String, tier: UInt8)] = [
            ("这是一个示例句子 sample text", 1),
            ("低置信度示例 low confidence", 3),
        ]
        let lineHeight: CGFloat = 24
        let totalHeight = lineHeight * CGFloat(lines.count)
        var top = (bounds.height + totalHeight) / 2

        for (text, tier) in lines {
            let size = (text as NSString).size(withAttributes: attrs)
            let origin = CGPoint(
                x: (bounds.width - size.width) / 2,
                y: top - size.height
            )
            let textLayer = CATextLayer()
            textLayer.string = NSAttributedString(string: text, attributes: attrs)
            textLayer.frame = CGRect(origin: origin, size: size)
            textLayer.contentsScale = window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor ?? 2
            layer.addSublayer(textLayer)

            // split the line into equal segments, one category each
            let segW = size.width / CGFloat(categories.count)
            for (i, category) in categories.enumerated() {
                let rect = CGRect(
                    x: origin.x + segW * CGFloat(i),
                    y: origin.y,
                    width: segW,
                    height: size.height
                )
                let finding = Finding(
                    category: category, ruleId: "", message: "",
                    start: 0, end: 0, suggestions: [], tier: tier
                )
                for sub in UnderlineDrawing.layers(
                    for: finding, rect: rect, appearance: underlineAppearance
                ) {
                    layer.addSublayer(sub)
                }
            }
            top -= lineHeight
        }
        CATransaction.commit()
    }
}

private struct UnderlinePreview: NSViewRepresentable {
    var appearance: UnderlineAppearance

    func makeNSView(context: Context) -> UnderlinePreviewNSView {
        let view = UnderlinePreviewNSView()
        view.underlineAppearance = appearance
        return view
    }

    func updateNSView(_ nsView: UnderlinePreviewNSView, context: Context) {
        nsView.underlineAppearance = appearance
    }
}
