import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Frontmost non-DeAI app bundle id (for "add current app").
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
