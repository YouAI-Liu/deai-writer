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

    var body: some View {
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
            Section("应用规则") {
                ForEach(settings.sortedAppRules, id: \.key) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.key)
                                .font(.callout.monospaced())
                            Text(entry.value.enabled
                                 ? (entry.value.markdown ? "启用" : "启用(不含 Markdown)")
                                 : "停用")
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
                        settings.appRules[newBundleId] = AppRule()
                        newBundleId = ""
                    }
                    .disabled(newBundleId.isEmpty)
                    if let cur = currentBundleId, !cur.isEmpty {
                        Button("添加当前应用") {
                            settings.appRules[cur] = AppRule()
                        }
                    }
                }
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

    private func binding(for bundleId: String, enabled: Bool) -> Binding<Bool> {
        Binding(
            get: {
                let rule = settings.appRules[bundleId] ?? AppRule()
                return enabled ? rule.enabled : rule.markdown
            },
            set: { v in
                var rule = settings.appRules[bundleId] ?? AppRule()
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
