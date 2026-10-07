import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Frontmost non-DeAI app bundle id (for "add current app").
    var currentBundleId: String?
    @State private var newBundleId = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("设置")
                    .font(DeAIDesign.font(27, weight: .semibold)).tracking(-0.8)
                section("检查类别") {
                    VStack(spacing: 18) {
                        Toggle("语法", isOn: $settings.grammar)
                        Toggle("中文 AI 腔", isOn: $settings.aiToneZh)
                        Toggle("英文 AI 腔", isOn: $settings.aiToneEn)
                        Toggle("Markdown 残留", isOn: $settings.markdown)
                    }
                    .toggleStyle(DeAIToggleStyle())
                }
                section("敏感度") {
                    SensitivityControl(selection: $settings.sensitivity)
                }
                section("应用规则") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(settings.sortedAppRules, id: \.key) { entry in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(entry.key).font(DeAIDesign.font(12))
                                        .textSelection(.enabled)
                                    Spacer()
                                    Button {
                                        settings.appRules.removeValue(forKey: entry.key)
                                    } label: {
                                        Image(systemName: "trash").font(DeAIDesign.font(12, weight: .medium))
                                    }
                                    .buttonStyle(.plain).foregroundStyle(DeAIDesign.muted)
                                    .accessibilityLabel("移除 \(entry.key)")
                                }
                                HStack(spacing: 24) {
                                    Toggle("启用", isOn: binding(for: entry.key, enabled: true))
                                    Toggle("Markdown", isOn: binding(for: entry.key, enabled: false))
                                }
                                .toggleStyle(DeAIToggleStyle())
                                Divider()
                            }
                        }
                        HStack(spacing: 10) {
                            TextField("应用 Bundle ID", text: $newBundleId)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(DeAIDesign.canvas, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel("应用 Bundle ID")
                            Button("添加") {
                                guard !newBundleId.isEmpty else { return }
                                settings.appRules[newBundleId] = AppRule()
                                newBundleId = ""
                            }
                            .buttonStyle(DeAIButtonStyle(compact: true))
                            .disabled(newBundleId.isEmpty)
                            .opacity(newBundleId.isEmpty ? 0.4 : 1)
                        }
                        if let cur = currentBundleId, !cur.isEmpty {
                            Button("添加当前应用") { settings.appRules[cur] = AppRule() }
                                .buttonStyle(.plain).underline()
                        }
                    }
                }
                section("已停用规则") {
                    VStack(alignment: .leading, spacing: 14) {
                        if settings.disabledRuleIds.isEmpty {
                            Text("无已停用规则")
                                .foregroundStyle(DeAIDesign.muted)
                        } else {
                            ForEach(Array(settings.disabledRuleIds).sorted(), id: \.self) { id in
                                HStack {
                                    Text(id).font(DeAIDesign.font(12)).textSelection(.enabled)
                                    Spacer()
                                    Button("重新启用") { settings.disabledRuleIds.remove(id) }
                                        .buttonStyle(DeAIButtonStyle(compact: true))
                                }
                            }
                        }
                    }
                }
            }
            .padding(30)
        }
        .font(DeAIDesign.font())
        .foregroundStyle(DeAIDesign.ink)
        .background(DeAIDesign.canvas)
        .preferredColorScheme(.light)
        .frame(width: 540, height: 700)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(DeAIDesign.font(12, weight: .medium))
            content().padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(DeAIDesign.paper, in: RoundedRectangle(cornerRadius: DeAIDesign.radius))
        }
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
