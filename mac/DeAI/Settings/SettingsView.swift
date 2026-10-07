import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Frontmost non-DeAI app bundle id (for "add current app").
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
        .frame(width: 480, height: 560)
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
