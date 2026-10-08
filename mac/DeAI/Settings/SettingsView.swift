import AppKit
import Carbon
import Combine
import SwiftUI

/// Settings window tabs — used for deep links like the card's 编辑词条….
enum SettingsTabID: Int {
    case check = 0
    case underline
    case ai
    case personal
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Frontmost non-DeAI app bundle id (for "add current app").
    var currentBundleId: String?
    /// Outer tab the view opens on (tests mount each pane directly):
    /// 0 = 检查, 1 = 下划线外观, 2 = AI 改写, 3 = 个人.
    var initialTab: Int
    /// Live controller when shown from the app — powers the hotkey
    /// recorder's pause hook and registration-error display.
    var controller: AppController?
    /// Capture hook: render the AI tab's recorder in its recording state.
    var hotkeyRecordingPreview: Bool
    @State private var selectedTab: Int

    init(settings: AppSettings, currentBundleId: String? = nil,
         initialTab: Int = 0, controller: AppController? = nil,
         hotkeyRecordingPreview: Bool = false) {
        self.settings = settings
        self.currentBundleId = currentBundleId
        self.initialTab = initialTab
        self.controller = controller
        self.hotkeyRecordingPreview = hotkeyRecordingPreview
        _selectedTab = State(initialValue: initialTab)
    }

    private var lang: UILanguage { settings.uiLanguage }

    var body: some View {
        TabView(selection: $selectedTab) {
            CheckSettingsTab(settings: settings, currentBundleId: currentBundleId)
                .tabItem { Label(L10n.t(.tabCheck, lang), systemImage: "checklist") }
                .tag(0)
            UnderlineSettingsTab(settings: settings)
                .tabItem { Label(L10n.t(.tabUnderline, lang), systemImage: "textformat.underline") }
                .tag(1)
            AISettingsTab(
                settings: settings, controller: controller,
                recordingPreview: hotkeyRecordingPreview
            )
                .tabItem { Label(L10n.t(.tabAI, lang), systemImage: "wand.and.stars") }
                .tag(2)
            PersonalSettingsTab(lexicon: settings.lexicon)
                .tabItem { Label(L10n.t(.tabPersonal, lang), systemImage: "person.text.rectangle") }
                .tag(3)
        }
        .font(DeAIDesign.font())
        .foregroundStyle(DeAIDesign.text)
        .tint(DeAIDesign.accent)
        .background(DeAIDesign.background)
        .frame(width: 560, height: 660)
        .environment(\.deaiUILanguage, settings.uiLanguage)
    }
}

/// Titled card section shared by every settings tab (DeAIDesign surface).
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(DeAIDesign.titleFont(14))
            content
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    DeAIDesign.surface,
                    in: RoundedRectangle(cornerRadius: DeAIDesign.radius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DeAIDesign.radius)
                        .strokeBorder(DeAIDesign.border, lineWidth: 0.5)
                }
        }
    }
}

/// Scroll container shared by every settings tab.
private struct SettingsTabScroll<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(30)
        }
        .font(DeAIDesign.font())
        .foregroundStyle(DeAIDesign.text)
        .background(DeAIDesign.background)
    }
}

// MARK: - 检查

/// Check categories, sensitivity, app-type groups, per-app exceptions and
/// disabled rules.
private struct CheckSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.deaiUILanguage) private var lang
    var currentBundleId: String?

    @State private var newBundleId = ""

    var body: some View {
        SettingsTabScroll {
            SettingsSection(L10n.t(.languageRow, lang)) {
                LanguagePicker(selection: $settings.uiLanguage)
            }
            SettingsSection(L10n.t(.sectionCategories, lang)) {
                VStack(spacing: 18) {
                    Toggle(L10n.t(.catGrammar, lang), isOn: $settings.grammar)
                    Toggle(L10n.t(.catAIToneZh, lang), isOn: $settings.aiToneZh)
                    Toggle(L10n.t(.catAIToneEn, lang), isOn: $settings.aiToneEn)
                    Toggle(L10n.t(.catMarkdown, lang), isOn: $settings.markdown)
                    Toggle(L10n.t(.catPersonal, lang), isOn: $settings.personal)
                }
                .toggleStyle(DeAIToggleStyle())
            }
            SettingsSection(L10n.t(.sectionSensitivity, lang)) {
                SensitivityControl(selection: $settings.sensitivity)
            }
            SettingsSection(L10n.t(.sectionAppGroups, lang)) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(AppGroup.configurable, id: \.self) { group in
                        let rule = settings.groupRules[group]
                            ?? AppGroup.defaultRule(for: group)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.displayName(lang))
                                    Text(group.examples(lang))
                                        .font(DeAIDesign.font(10))
                                        .foregroundStyle(DeAIDesign.muted)
                                }
                                Spacer()
                                Toggle(L10n.t(.toggleEnabled, lang), isOn: groupEnabledBinding(group))
                                    .labelsHidden()
                                    .toggleStyle(DeAIToggleStyle(showsLabel: false))
                            }
                            HStack(spacing: 8) {
                                ForEach(CheckKind.allCases, id: \.self) { kind in
                                    Toggle(
                                        kind.shortName(lang),
                                        isOn: groupCheckBinding(group, kind)
                                    )
                                    .toggleStyle(DeAIChipToggleStyle())
                                }
                            }
                            .font(DeAIDesign.font(11))
                            .disabled(!rule.enabled)
                        }
                    }
                }
            }
            SettingsSection(L10n.t(.sectionAppExceptions, lang)) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(settings.sortedAppRules, id: \.key) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.key)
                                        .font(DeAIDesign.font(12))
                                        .textSelection(.enabled)
                                    Text(
                                        (entry.value.enabled
                                            ? (entry.value.markdown
                                                ? L10n.t(.ruleEnabled, lang)
                                                : L10n.t(.ruleEnabledNoMarkdown, lang))
                                            : L10n.t(.ruleDisabled, lang))
                                            + " · \(AppGroup.group(for: entry.key).displayName(lang))"
                                    )
                                    .font(DeAIDesign.font(10))
                                    .foregroundStyle(DeAIDesign.muted)
                                }
                                Spacer()
                                Button {
                                    settings.appRules.removeValue(forKey: entry.key)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(DeAIDesign.font(12, weight: .medium))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(DeAIDesign.muted)
                                .help(L10n.t(.deleteTooltip, lang))
                                .accessibilityLabel(L10n.f(.removeAppA11y, lang, entry.key))
                            }
                            HStack(spacing: 24) {
                                Toggle(L10n.t(.toggleEnabled, lang), isOn: binding(for: entry.key, enabled: true))
                                Toggle("Markdown", isOn: binding(for: entry.key, enabled: false))
                            }
                            .toggleStyle(DeAIToggleStyle())
                            Divider()
                        }
                    }
                    HStack(spacing: 10) {
                        TextField(L10n.t(.bundlePlaceholder, lang), text: $newBundleId)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(
                                DeAIDesign.sidebar,
                                in: RoundedRectangle(cornerRadius: DeAIDesign.controlRadius)
                            )
                            .accessibilityLabel(L10n.t(.bundleIdA11y, lang))
                        Button(L10n.t(.addButton, lang)) {
                            guard !newBundleId.isEmpty else { return }
                            settings.appRules[newBundleId] =
                                settings.defaultAppRule(for: newBundleId)
                            newBundleId = ""
                        }
                        .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                        .disabled(newBundleId.isEmpty)
                        .opacity(newBundleId.isEmpty ? 0.4 : 1)
                    }
                    if let cur = currentBundleId, !cur.isEmpty {
                        Button(L10n.t(.addCurrentApp, lang)) {
                            settings.appRules[cur] = settings.defaultAppRule(for: cur)
                        }
                        .buttonStyle(.plain)
                        .underline()
                    }
                }
            }
            SettingsSection(L10n.t(.sectionDisabledRules, lang)) {
                VStack(alignment: .leading, spacing: 14) {
                    if settings.disabledRuleIds.isEmpty {
                        Text(L10n.t(.noDisabledRules, lang))
                            .foregroundStyle(DeAIDesign.muted)
                    } else {
                        ForEach(Array(settings.disabledRuleIds).sorted(), id: \.self) { id in
                            HStack {
                                Text(id)
                                    .font(DeAIDesign.font(12))
                                    .textSelection(.enabled)
                                Spacer()
                                Button(L10n.t(.reenableButton, lang)) {
                                    settings.disabledRuleIds.remove(id)
                                }
                                .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                            }
                        }
                    }
                }
            }
        }
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

/// 中文 / English segmented control in the SensitivityControl style. The
/// option labels are always native so the row is findable in either UI.
private struct LanguagePicker: View {
    @Binding var selection: UILanguage
    @DeAIReducedMotion private var reduceMotion: Bool
    @Namespace private var highlight

    private var titles: [String] { ["中文", "English"] }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(UILanguage.allCases.enumerated()), id: \.offset) { index, lang in
                Button {
                    withAnimation(DeAIDesign.motion(reduceMotion)) { selection = lang }
                } label: {
                    Text(titles[index])
                        .font(DeAIDesign.font(12, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(selection == lang ? DeAIDesign.text : DeAIDesign.secondaryText)
                        .background {
                            if selection == lang {
                                let capsule = DeAIDesign.pill.fill(DeAIDesign.surface)
                                if reduceMotion {
                                    capsule.transition(.opacity)
                                } else {
                                    capsule.matchedGeometryEffect(id: "lang", in: highlight)
                                }
                            }
                        }
                        .overlay {
                            if selection == lang {
                                DeAIDesign.pill.strokeBorder(DeAIDesign.border, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(titles[index])
                .accessibilityAddTraits(selection == lang ? .isSelected : [])
            }
        }
        .padding(5)
        .background(DeAIDesign.track, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t(.languageRow, .zh))
    }
}

// MARK: - 下划线外观

/// Underline appearance editor with live preview. An empty `colorHex`
/// means 跟随主题 — the color well shows the resolved palette color and a
/// per-category reset restores it.
private struct UnderlineSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.deaiUILanguage) private var lang

    private static let categories: [Category] = [
        .grammar, .aiToneZh, .aiToneEn, .markdown, .personal,
    ]

    var body: some View {
        SettingsTabScroll {
            SettingsSection(L10n.t(.sectionPreview, lang)) {
                UnderlinePreview(appearance: settings.underline, lang: lang)
                    .frame(height: 64)
            }
            SettingsSection(L10n.t(.sectionCategoryStyles, lang)) {
                VStack(spacing: 16) {
                    ForEach(Self.categories, id: \.self) { category in
                        HStack {
                            Text(category.displayName(lang))
                            Spacer()
                            if settings.underline.style(for: category).colorHex.isEmpty {
                                Button(L10n.t(.followTheme, lang)) {
                                    // already following; keeps the label tappable/consistent
                                }
                                .buttonStyle(.plain)
                                .font(DeAIDesign.font(10))
                                .foregroundStyle(DeAIDesign.muted)
                                .disabled(true)
                            } else {
                                Button(L10n.t(.followTheme, lang)) {
                                    var style = settings.underline.style(for: category)
                                    style.colorHex = ""
                                    var appearance = settings.underline
                                    appearance.styles[
                                        UnderlineAppearance.key(for: category)
                                    ] = style
                                    settings.underline = appearance
                                }
                                .buttonStyle(.plain)
                                .font(DeAIDesign.font(10))
                                .underline()
                            }
                            ColorPicker(
                                L10n.t(.colorLabel, lang),
                                selection: colorBinding(for: category),
                                supportsOpacity: false
                            )
                            .labelsHidden()
                            Picker(L10n.t(.shapeLabel, lang), selection: shapeBinding(for: category)) {
                                ForEach(UnderlineShape.allCases, id: \.self) { shape in
                                    Text(shape.displayName(lang)).tag(shape)
                                }
                            }
                            .labelsHidden()
                            .frame(width: lang == .en ? 110 : 96)
                        }
                    }
                }
            }
            SettingsSection(L10n.t(.sectionGlobal, lang)) {
                VStack(spacing: 16) {
                    sliderRow(L10n.t(.thicknessLabel, lang), value: $settings.underline.thickness, range: 0.5...4)
                    sliderRow(L10n.t(.opacityLabel, lang), value: $settings.underline.opacity, range: 0.2...1)
                    sliderRow(L10n.t(.offsetLabel, lang), value: $settings.underline.offset, range: -2...4)
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(L10n.t(.dimLowConfidence, lang), isOn: $settings.underline.dimLowConfidence)
                        Toggle(L10n.t(.highlightFill, lang), isOn: $settings.underline.highlightFill)
                    }
                    .toggleStyle(DeAIToggleStyle())
                    HStack {
                        Spacer()
                        Button(L10n.t(.restoreDefaults, lang)) {
                            settings.underline = .default
                        }
                        .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                    }
                }
            }
        }
    }

    private func sliderRow(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>
    ) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
                .tint(DeAIDesign.secondaryText)
            Text(String(format: "%.1f", value.wrappedValue))
                .font(DeAIDesign.font(11).monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
    }

    /// The well always shows the resolved color: the theme palette color
    /// when the style is 跟随主题 (`colorHex == ""`), the override otherwise.
    private func colorBinding(for category: Category) -> Binding<Color> {
        Binding(
            get: {
                let hex = settings.underline.style(for: category).colorHex
                if hex.isEmpty {
                    return Color(nsColor: DeAIDesign.underlineColor(for: category))
                }
                return Color(hex: hex)
            },
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
}

// MARK: - AI 改写

/// Provider management + hotkey for the AI rewrite feature.
private struct AISettingsTab: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.deaiUILanguage) private var lang
    var controller: AppController?
    /// Capture hook: show the recorder mid-recording.
    var recordingPreview = false

    /// API key draft — the saved key is never echoed back into the field.
    @State private var keyDraft = ""
    @State private var keySaved = false
    /// OpenCode Go only: true when the model isn't one of the known ids.
    @State private var customModel = false
    @State private var testing = false
    @State private var testStatus: String?
    @State private var hotkeyError: String?
    @State private var showingAddProvider = false
    /// Skill being viewed/edited in the sheet (nil = closed).
    @State private var editingSkill: RewriteSkill?

    /// Observes the optional controller's @Published error even though a
    /// plain `var` can't be @ObservedObject.
    private var hotkeyErrorPublisher: AnyPublisher<String?, Never> {
        controller?.$hotkeyError.eraseToAnyPublisher()
            ?? Just(nil).eraseToAnyPublisher()
    }

    var body: some View {
        SettingsTabScroll {
            SettingsSection(L10n.t(.sectionProviders, lang)) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(settings.providers) { p in
                        HStack {
                            Image(
                                systemName: p.id == settings.activeProviderId
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(DeAIDesign.font(12))
                                Text(p.model.isEmpty ? p.preset.label(lang) : p.model)
                                    .font(DeAIDesign.font(10))
                                    .foregroundStyle(DeAIDesign.muted)
                            }
                            Spacer()
                            Button {
                                settings.deleteProvider(id: p.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(DeAIDesign.font(12, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(DeAIDesign.muted)
                            .help(L10n.t(.deleteTooltip, lang))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            settings.activeProviderId = p.id
                        }
                    }
                    // plain Button + popover: a .borderlessButton Menu renders
                    // its label through NSPopUpButton, which ignores
                    // foregroundStyle → black text on dark cards (QA r5).
                    Button {
                        showingAddProvider = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(L10n.t(.addProvider, lang))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(DeAIDesign.font(8, weight: .semibold))
                        }
                        .font(DeAIDesign.font(12))
                        .foregroundStyle(DeAIDesign.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            DeAIDesign.surface,
                            in: RoundedRectangle(cornerRadius: DeAIDesign.controlRadius)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: DeAIDesign.controlRadius)
                                .strokeBorder(DeAIDesign.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t(.addProvider, lang))
                    .popover(
                        isPresented: $showingAddProvider, arrowEdge: .bottom
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(ProviderPreset.allCases, id: \.self) { preset in
                                AddProviderRow(preset: preset, lang: lang) {
                                    _ = settings.addProvider(preset: preset)
                                    showingAddProvider = false
                                }
                            }
                        }
                        .padding(4)
                        .background(DeAIDesign.background)
                    }
                }
            }
            if let provider = settings.activeProvider {
                providerEditor(provider)
            }
            SkillsSectionView(
                settings: settings, store: settings.skills,
                editingSkill: $editingSkill
            )
            SettingsSection(L10n.t(.sectionShortcut, lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(L10n.t(.shortcutLabel, lang))
                        Spacer()
                        ShortcutRecorder(
                            hotkey: $settings.rewriteHotkey,
                            recording: recordingPreview,
                            heldModifiers: recordingPreview
                                ? UInt32(controlKey | optionKey) : 0,
                            onRecordingChanged: {
                                controller?.setHotkeyPaused($0)
                            }
                        )
                        Button(L10n.t(.restoreDefaults, lang)) {
                            settings.rewriteHotkey = .default
                        }
                        .font(DeAIDesign.font(11))
                        .foregroundStyle(DeAIDesign.muted)
                        .buttonStyle(.plain)
                    }
                    Text(L10n.t(.shortcutCaption, lang))
                        .font(DeAIDesign.font(10))
                        .foregroundStyle(DeAIDesign.muted)
                    if let hotkeyError {
                        Text(hotkeyError)
                            .font(DeAIDesign.font(11))
                            .foregroundStyle(DeAIDesign.danger)
                    }
                }
            }
        }
        .onAppear {
            refreshKeyState()
            // in-place edits don't fire the directory watcher — refresh
            // the skill list every time the tab appears
            settings.skills.reload()
        }
        .onReceive(hotkeyErrorPublisher) { hotkeyError = $0 }
        .onChange(of: settings.activeProviderId) { _ in refreshKeyState() }
        // if the skill being edited is deleted (here or externally),
        // close the sheet — saving a gone skill would re-create its file
        .onReceive(settings.skills.$skills.map { $0.map(\.id) }) { ids in
            if let editing = editingSkill,
               !editing.isBuiltin, !ids.contains(editing.id) {
                editingSkill = nil
            }
        }
        .sheet(item: $editingSkill) { skill in
            SkillEditSheet(
                skill: skill, store: settings.skills,
                onDuplicate: { copy in editingSkill = copy }
            )
            .id(skill.id)
            .environment(\.deaiUILanguage, lang)
        }
    }

    @ViewBuilder
    private func providerEditor(_ p: ProviderConfig) -> some View {
        SettingsSection(L10n.f(.configSection, lang, p.name)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L10n.t(.nameLabel, lang))
                    Spacer()
                    TextField(L10n.t(.nameLabel, lang), text: providerBinding(p.id, \.name))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }
                HStack {
                    Text(L10n.t(.formatLabel, lang))
                    Spacer()
                    SettingsPickButton(
                        label: L10n.t(.formatLabel, lang),
                        selection: providerBinding(
                            p.id, \.format, fallback: .openAIChat
                        ),
                        options: APIFormat.allCases,
                        optionLabel: { $0.label }
                    )
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
                        Text(L10n.t(.modelLabel, lang))
                        Spacer()
                        TextField(L10n.t(.modelIdPlaceholder, lang), text: providerBinding(p.id, \.model))
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
                    .frame(minWidth: 120, maxWidth: 200)
                    Button(L10n.t(.saveButton, lang)) { saveKey() }
                        .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                        .disabled(keyDraft.isEmpty)
                        .fixedSize()
                    if keySaved && keyDraft.isEmpty {
                        Button(L10n.t(.clearButton, lang)) { clearKey() }
                            .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                            .fixedSize()
                    }
                    Text(keySaved ? L10n.t(.keySaved, lang) : L10n.t(.keyNotSet, lang))
                        .font(DeAIDesign.font(10))
                        .foregroundStyle(keySaved ? .green : DeAIDesign.muted)
                        .fixedSize()
                        .lineLimit(1)
                }
                HStack {
                    Button(testing ? L10n.t(.testing, lang) : L10n.t(.testConnection, lang)) { testConnection(p) }
                        .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                        .disabled(testing)
                    if let testStatus {
                        Text(testStatus)
                            .font(DeAIDesign.font(10))
                            .foregroundStyle(
                                testStatus.hasPrefix("✓") ? DeAIDesign.acceptGreen : DeAIDesign.danger
                            )
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func modelPicker(_ p: ProviderConfig) -> some View {
        HStack {
            Text(L10n.t(.modelLabel, lang))
            Spacer()
            SettingsPickButton(
                label: L10n.t(.modelLabel, lang), selection: modelSelection(p),
                options: OpenCodeGoModels.all + ["__custom__"],
                optionLabel: { $0 == "__custom__" ? L10n.t(.customModelTag, lang) : $0 }
            )
            .frame(width: 280)
        }
        if customModel {
            HStack {
                Text(L10n.t(.customModelLabel, lang))
                Spacer()
                TextField(L10n.t(.modelIdPlaceholder, lang), text: providerBinding(p.id, \.model))
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

    /// Never deletes: SecureField's onCommit also fires when the field
    /// merely loses focus, and with the draft already cleared after a save
    /// that used to wipe the stored key. Deleting is `clearKey()` only.
    private func saveKey() {
        guard case .save(let key) = KeyAction(draft: keyDraft),
              let id = settings.activeProvider?.id else { return }
        settings.secrets.set(key, for: id.uuidString)
        keyDraft = ""
        keySaved = settings.secrets.get(id.uuidString) != nil
    }

    private func clearKey() {
        guard let id = settings.activeProvider?.id else { return }
        settings.secrets.set(nil, for: id.uuidString)
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
                testStatus = L10n.f(.testSucceeded, settings.uiLanguage, ms)
            } catch {
                testStatus = error.deaiMessage(settings.uiLanguage)
            }
            testing = false
        }
    }
}

// MARK: - 改写技能

/// AI 改写 tab's 改写技能 section: fixed safety rules, per-language
/// pickers, the skill list, and 导入技能….
struct SkillsSectionView: View {
    @ObservedObject var settings: AppSettings
    /// Observed directly — the list must re-render when the store's
    /// @Published skills change (import/delete/external edits).
    @ObservedObject var store: RewriteSkillStore
    @Environment(\.deaiUILanguage) private var lang
    @Binding var editingSkill: RewriteSkill?
    @State private var safetyExpanded = false
    @State private var confirmDelete: RewriteSkill?
    @State private var importError: String?

    init(settings: AppSettings, store: RewriteSkillStore,
         editingSkill: Binding<RewriteSkill?>, safetyExpanded: Bool = false) {
        self.settings = settings
        self.store = store
        _editingSkill = editingSkill
        _safetyExpanded = State(initialValue: safetyExpanded)
    }

    var body: some View {
        SettingsSection(L10n.t(.sectionSkills, lang)) {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup(
                    isExpanded: $safetyExpanded
                ) {
                    if lang == .en {
                        Text(L10n.t(.promptOriginalLanguageNote, lang))
                            .font(DeAIDesign.font(10))
                            .foregroundStyle(DeAIDesign.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(RewritePrompt.safetyBlock)
                        .font(DeAIDesign.font(11))
                        .foregroundStyle(DeAIDesign.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            DeAIDesign.sidebar,
                            in: RoundedRectangle(
                                cornerRadius: DeAIDesign.controlRadius
                            )
                        )
                } label: {
                    Text(L10n.t(.safetyDisclosure, lang))
                        .font(DeAIDesign.font(12))
                        .foregroundStyle(DeAIDesign.text)
                }
                .tint(DeAIDesign.muted)

                HStack(spacing: 12) {
                    skillPicker(
                        label: L10n.t(.skillForZh, lang),
                        language: .zh,
                        selection: $settings.rewriteSkillZh
                    )
                    skillPicker(
                        label: L10n.t(.skillForEn, lang),
                        language: .en,
                        selection: $settings.rewriteSkillEn
                    )
                }

                ForEach(store.skills) { skill in
                    SkillRow(
                        skill: skill, lang: lang,
                        onEdit: { editingSkill = skill },
                        onReveal: { reveal(skill) },
                        onDelete: skill.isBuiltin
                            ? nil : { confirmDelete = skill }
                    )
                    if skill.id != store.skills.last?.id {
                        Divider().overlay(DeAIDesign.border.opacity(0.5))
                    }
                }

                HStack(spacing: 10) {
                    Button(L10n.t(.skillImport, lang)) { importSkill() }
                        .buttonStyle(
                            DeAIButtonStyle(secondary: true, compact: true)
                        )
                    Button(L10n.t(.showInFinder, lang)) {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [store.fileToReveal]
                        )
                    }
                    .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                }
                if let importError {
                    Text(importError)
                        .font(DeAIDesign.font(10))
                        .foregroundStyle(DeAIDesign.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .confirmationDialog(
            L10n.f(
                .skillDeleteTitle, lang,
                confirmDelete?.displayName(lang) ?? ""
            ),
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.t(.deleteTooltip, lang), role: .destructive) {
                delete(confirmDelete)
            }
            Button(L10n.t(.cancelButton, lang), role: .cancel) {
                confirmDelete = nil
            }
        } message: {
            Text(L10n.t(.skillDeleteMessage, lang))
        }
    }

    /// zh picker offers zh|any skills, en picker en|any; a missing
    /// selection resolves to the built-in at display time.
    private func skillPicker(
        label: String, language: SkillLanguage, selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DeAIDesign.font(10))
                .foregroundStyle(DeAIDesign.muted)
            SkillPickButton(
                skills: store.eligible(for: language),
                selection: selection, lang: lang
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reveal(_ skill: RewriteSkill) {
        let url = skill.isBuiltin
            ? store.directory
            : store.directory.appendingPathComponent("\(skill.id).md")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func delete(_ skill: RewriteSkill?) {
        guard let skill, !skill.isBuiltin else { return }
        store.delete(id: skill.id)
        // a deleted selection falls back to the built-in
        if settings.rewriteSkillZh == skill.id {
            settings.rewriteSkillZh = RewriteSkillStore.builtinId
        }
        if settings.rewriteSkillEn == skill.id {
            settings.rewriteSkillEn = RewriteSkillStore.builtinId
        }
        confirmDelete = nil
    }

    private func importSkill() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = L10n.t(.skillImport, lang)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch store.importSkill(from: url) {
        case .success:
            importError = nil
        case .failure(let error):
            importError = skillErrorText(error)
        }
    }

    private func skillErrorText(_ error: SkillError) -> String {
        switch error {
        case .tooLarge(let size, let max):
            return L10n.f(.skillTooLarge, lang, size, max)
        case .notMarkdown:
            return L10n.t(.skillNotMarkdown, lang)
        case .emptyName, .unreadable:
            return L10n.t(.skillUnreadable, lang)
        }
    }
}

/// One skill row: name + language chip + size/estimate + warn badge +
/// view/edit, reveal, delete actions.
private struct SkillRow: View {
    let skill: RewriteSkill
    var lang: UILanguage
    var onEdit: () -> Void
    var onReveal: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(skill.displayName(lang))
                        .font(DeAIDesign.font(12))
                        .lineLimit(1)
                    SkillLangChip(language: skill.language, lang: lang)
                    if skill.isLong {
                        Text(L10n.t(.skillLongWarning, lang))
                            .font(DeAIDesign.font(9))
                            .foregroundStyle(DeAIDesign.danger)
                            .lineLimit(1)
                    }
                }
                Text(
                    L10n.f(
                        .skillSize, lang, skill.body.count,
                        skill.estimatedTokens
                    )
                )
                .font(DeAIDesign.font(10).monospacedDigit())
                .foregroundStyle(DeAIDesign.muted)
            }
            Spacer()
            Button(L10n.t(.skillViewEdit, lang), action: onEdit)
                .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
            if !skill.isBuiltin {
                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .font(DeAIDesign.font(11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DeAIDesign.muted)
                .help(L10n.t(.showInFinder, lang))
                .accessibilityLabel(L10n.t(.showInFinder, lang))
            }
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(DeAIDesign.font(11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DeAIDesign.muted)
                .help(L10n.t(.deleteTooltip, lang))
                .accessibilityLabel(L10n.t(.deleteTooltip, lang))
            }
        }
    }
}

/// Small language tag chip on a skill row (中文 / English / 通用).
private struct SkillLangChip: View {
    let language: SkillLanguage
    var lang: UILanguage

    var body: some View {
        Text(language.displayName(lang))
            .font(DeAIDesign.font(9))
            .foregroundStyle(DeAIDesign.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                DeAIDesign.sidebar, in: DeAIDesign.pill
            )
            .overlay {
                DeAIDesign.pill
                    .strokeBorder(DeAIDesign.border, lineWidth: 0.5)
            }
    }
}

/// Theme-aware provider selection, avoiding NSPopUpButton's label colors.
private struct SettingsPickButton<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [Value]
    let optionLabel: (Value) -> String
    @Environment(\.isEnabled) private var enabled
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 6) {
                Text(optionLabel(selection)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(DeAIDesign.font(8, weight: .semibold))
            }
            .font(DeAIDesign.font(12))
            .foregroundStyle(enabled ? DeAIDesign.text : DeAIDesign.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DeAIDesign.surface,
                        in: RoundedRectangle(cornerRadius: DeAIDesign.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DeAIDesign.controlRadius)
                    .strokeBorder(DeAIDesign.border, lineWidth: 1)
            }
        }
        .buttonStyle(SettingsPickButtonStyle())
        .accessibilityLabel(label)
        .accessibilityValue(optionLabel(selection))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                        open = false
                    } label: {
                        SettingsPickOptionRow(
                            title: optionLabel(option), selected: option == selection
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .frame(minWidth: 280)
            .background(DeAIDesign.background)
        }
    }
}

/// Keep a disabled format's muted label readable; PlainButtonStyle dims it again.
private struct SettingsPickButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct SettingsPickOptionRow: View {
    let title: String
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: selected ? "checkmark" : "")
                .font(DeAIDesign.font(9, weight: .bold))
                .frame(width: 12)
            Text(title).font(DeAIDesign.font(12))
            Spacer(minLength: 8)
        }
        .foregroundStyle(DeAIDesign.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DeAIDesign.controlRadius)
                .fill(hovering ? DeAIDesign.sidebar : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Skill selection control — plain Button + popover (system Menu renders
/// black-on-dark; see AddProviderRow's note).
private struct SkillPickButton: View {
    let skills: [RewriteSkill]
    @Binding var selection: String
    var lang: UILanguage
    @State private var open = false

    private var current: RewriteSkill {
        skills.first { $0.id == selection }
            ?? skills.first { $0.isBuiltin }
            ?? skills[0]
    }

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 6) {
                Text(current.displayName(lang))
                    .font(DeAIDesign.font(11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(DeAIDesign.font(7, weight: .semibold))
            }
            .foregroundStyle(DeAIDesign.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                DeAIDesign.surface,
                in: RoundedRectangle(
                    cornerRadius: DeAIDesign.controlRadius
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: DeAIDesign.controlRadius)
                    .strokeBorder(DeAIDesign.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(current.displayName(lang))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(skills) { skill in
                    Button {
                        selection = skill.id
                        open = false
                    } label: {
                        SkillPickOptionRow(
                            skill: skill,
                            selected: skill.id == current.id,
                            lang: lang
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .frame(minWidth: 220)
            .background(DeAIDesign.background)
        }
    }
}

/// Popover row for the skill picker — hover highlight + checkmark +
/// language chip.
private struct SkillPickOptionRow: View {
    let skill: RewriteSkill
    var selected: Bool
    var lang: UILanguage
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: selected ? "checkmark" : "")
                .font(DeAIDesign.font(9, weight: .bold))
                .frame(width: 12)
            Text(skill.displayName(lang))
                .font(DeAIDesign.font(12))
                .lineLimit(1)
            Spacer(minLength: 8)
            SkillLangChip(language: skill.language, lang: lang)
        }
        .foregroundStyle(DeAIDesign.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DeAIDesign.controlRadius)
                .fill(hovering ? DeAIDesign.sidebar : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// View/edit sheet for one skill. Built-in: read-only + 复制为新技能.
/// User skills: name/description/language/body editable + 保存.
/// Internal (not private) so the debug showcase can render it directly.
struct SkillEditSheet: View {
    let skill: RewriteSkill
    let store: RewriteSkillStore
    /// Built-in copy-as-new → parent swaps the sheet's subject.
    var onDuplicate: ((RewriteSkill) -> Void)? = nil

    @Environment(\.deaiUILanguage) private var lang
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var desc: String
    @State private var language: SkillLanguage
    @State private var bodyText: String
    @State private var error: String?

    init(
        skill: RewriteSkill, store: RewriteSkillStore,
        onDuplicate: ((RewriteSkill) -> Void)? = nil
    ) {
        self.skill = skill
        self.store = store
        self.onDuplicate = onDuplicate
        _name = State(initialValue: skill.name)
        _desc = State(initialValue: skill.description)
        _language = State(initialValue: skill.language)
        _bodyText = State(initialValue: skill.body)
        _error = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(L10n.t(.skillNameLabel, lang))
                    .frame(width: 84, alignment: .leading)
                if skill.isBuiltin {
                    Text(skill.displayName(lang)).textSelection(.enabled)
                    Spacer()
                } else {
                    TextField(L10n.t(.skillNameLabel, lang), text: $name)
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 8) {
                Text(L10n.t(.skillDescLabel, lang))
                    .frame(width: 84, alignment: .leading)
                if skill.isBuiltin {
                    Text(skill.description).textSelection(.enabled)
                    Spacer()
                } else {
                    TextField(L10n.t(.skillDescLabel, lang), text: $desc)
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 8) {
                Text(L10n.t(.skillLanguageLabel, lang))
                    .frame(width: 84, alignment: .leading)
                if skill.isBuiltin {
                    SkillLangChip(language: skill.language, lang: lang)
                } else {
                    ForEach(SkillLanguage.allCases, id: \.self) { l in
                        Button {
                            language = l
                        } label: {
                            Text(l.displayName(lang))
                                .font(DeAIDesign.font(11))
                                .foregroundStyle(
                                    language == l
                                        ? DeAIDesign.text : DeAIDesign.muted
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(
                                    language == l
                                        ? DeAIDesign.surface : DeAIDesign.sidebar,
                                    in: DeAIDesign.pill
                                )
                                .overlay {
                                    DeAIDesign.pill.strokeBorder(
                                        language == l
                                            ? DeAIDesign.accent
                                            : DeAIDesign.border,
                                        lineWidth: 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            if skill.isBuiltin && lang == .en {
                Text(L10n.t(.promptOriginalLanguageNote, lang))
                    .font(DeAIDesign.font(10))
                    .foregroundStyle(DeAIDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if skill.isBuiltin {
                    ScrollView {
                        Text(skill.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    TextEditor(text: $bodyText)
                        .scrollContentBackground(.hidden)
                }
            }
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .background(
                    DeAIDesign.sidebar,
                    in: RoundedRectangle(
                        cornerRadius: DeAIDesign.controlRadius
                    )
                )
                .accessibilityLabel(L10n.t(.skillBodyLabel, lang))
            HStack {
                Text(
                    L10n.f(
                        .skillSize, lang, bodyText.count,
                        RewriteSkillStore.estimatedTokens(bodyText)
                    )
                )
                .font(DeAIDesign.font(10).monospacedDigit())
                .foregroundStyle(
                    bodyText.count > RewriteSkillStore.maxBodyLength
                        ? DeAIDesign.danger : DeAIDesign.muted
                )
                if let error {
                    Text(error)
                        .font(DeAIDesign.font(10))
                        .foregroundStyle(DeAIDesign.danger)
                }
                Spacer()
            }
            if skill.isBuiltin {
                Text(L10n.t(.builtinReadonlyNote, lang))
                    .font(DeAIDesign.font(10))
                    .foregroundStyle(DeAIDesign.muted)
            }
            HStack {
                if skill.isBuiltin {
                    Button(L10n.t(.skillDuplicate, lang)) {
                        onDuplicate?(store.duplicate(skill, language: lang))
                    }
                    .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                }
                Spacer()
                Button(L10n.t(.cancelButton, lang)) { dismiss() }
                    .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                if !skill.isBuiltin {
                    Button(L10n.t(.saveButton, lang)) { save() }
                        .buttonStyle(DeAIButtonStyle(compact: true))
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                                || bodyText.count
                                    > RewriteSkillStore.maxBodyLength
                        )
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
        .font(DeAIDesign.font())
        .foregroundStyle(DeAIDesign.text)
        .background(DeAIDesign.background)
    }

    private func save() {
        // a deleted skill must not be re-created by a stray Save
        guard store.skills.contains(where: { $0.id == skill.id }) else {
            error = L10n.t(.skillDeleted, lang)
            return
        }
        var updated = skill
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = desc.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        updated.language = language
        updated.body = bodyText
        switch store.save(updated) {
        case .success:
            dismiss()
        case .failure(let e):
            switch e {
            case .tooLarge(let size, let max):
                error = L10n.f(.skillTooLarge, lang, size, max)
            case .emptyName:
                error = L10n.t(.errEmptyTerm, lang)
            default:
                error = L10n.t(.skillUnreadable, lang)
            }
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
    var lang: UILanguage = .zh {
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        // BUG-04: a CATextLayer keeps the CGColor baked at build time —
        // resolve labelColor against OUR effective appearance or the sample
        // text stays black on the dark preview background.
        var textColor = NSColor.labelColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            textColor = NSColor.labelColor.cgColor
        }
        let font = NSFont.systemFont(ofSize: 14)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: textColor) ?? .labelColor,
        ]
        let categories: [Category] = [.grammar, .aiToneZh, .aiToneEn, .markdown]
        let lines: [(text: String, tier: UInt8)] = [
            (L10n.t(.previewLine1, lang), 1),
            (L10n.t(.previewLine2, lang), 3),
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
                    for: finding, rect: rect,
                    appearance: underlineAppearance,
                    colorAppearance: effectiveAppearance
                ) {
                    layer.addSublayer(sub)
                }
            }
            top -= lineHeight
        }
        CATransaction.commit()
    }
}

/// Popover row for "添加服务…" — full-width plain button with a sidebar-fill
/// hover highlight (Claude-style menu row).
private struct AddProviderRow: View {
    let preset: ProviderPreset
    var lang: UILanguage = .zh
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(preset.label(lang))
                .font(DeAIDesign.font(12))
                .foregroundStyle(DeAIDesign.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(
                        cornerRadius: DeAIDesign.controlRadius
                    )
                    .fill(hovering ? DeAIDesign.sidebar : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct UnderlinePreview: NSViewRepresentable {
    var appearance: UnderlineAppearance
    var lang: UILanguage

    func makeNSView(context: Context) -> UnderlinePreviewNSView {
        let view = UnderlinePreviewNSView()
        view.underlineAppearance = appearance
        view.lang = lang
        return view
    }

    func updateNSView(_ nsView: UnderlinePreviewNSView, context: Context) {
        nsView.underlineAppearance = appearance
        nsView.lang = lang
    }
}

// MARK: - 个人

/// Personal lexicon only — the AI-only style half moved to the AI tab's
/// 改写技能 section (RewriteSkillStore). Entries persist to
/// `~/Library/Application Support/DeAI/lexicon.json` (watched for external
/// edits).
private struct PersonalSettingsTab: View {
    @ObservedObject var lexicon: PersonalLexiconStore
    @Environment(\.deaiUILanguage) private var lang

    var body: some View {
        SettingsTabScroll {
            SettingsSection(L10n.t(.sectionLexicon, lang)) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(lexicon.entries) { entry in
                        LexiconEntryRow(
                            entry: binding(for: entry.id),
                            error: lexicon.validationError(for: entry, lang: lang),
                            onDelete: { lexicon.removeEntry(id: entry.id) }
                        )
                    }
                    HStack {
                        Button(L10n.t(.addEntry, lang)) {
                            lexicon.addDraft()
                        }
                        .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                        .disabled(lexicon.entries.count >= PersonalLexiconStore.maxEntries)
                        .opacity(
                            lexicon.entries.count >= PersonalLexiconStore.maxEntries
                                ? 0.4 : 1
                        )
                        .accessibilityLabel(L10n.t(.addEntry, lang))
                        Spacer()
                        Text("\(lexicon.entries.count)/\(PersonalLexiconStore.maxEntries)")
                            .font(DeAIDesign.font(10).monospacedDigit())
                            .foregroundStyle(DeAIDesign.muted)
                    }
                    Text(L10n.t(.lexiconCaption, lang))
                        .font(DeAIDesign.font(10))
                        .foregroundStyle(DeAIDesign.muted)
                    Text(L10n.t(.lexiconSharedNote, lang))
                        .font(DeAIDesign.font(10))
                        .foregroundStyle(DeAIDesign.muted)
                }
            }
        }
    }

    private func binding(for id: UUID) -> Binding<LexiconEntry> {
        Binding(
            get: {
                lexicon.entries.first { $0.id == id }
                    ?? LexiconEntry(kind: .replace, term: "")
            },
            set: { lexicon.updateEntry($0) }
        )
    }
}

/// One lexicon row: kind picker, 原词, (→ 替换为 when 替换), match picker,
/// trash — with inline validation in DeAIDesign.danger.
private struct LexiconEntryRow: View {
    @Binding var entry: LexiconEntry
    @Environment(\.deaiUILanguage) private var lang
    /// Inline validation message (empty term / too long / duplicate).
    var error: String?
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Picker(L10n.t(.kindLabel, lang), selection: $entry.kind) {
                    ForEach(LexiconEntry.Kind.allCases, id: \.self) { kind in
                        Text(kind.displayName(lang)).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: lang == .en ? 96 : 76)

                TextField(L10n.t(.termPlaceholder, lang), text: $entry.term)
                    .textFieldStyle(.plain)
                    .font(DeAIDesign.font(12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        DeAIDesign.sidebar,
                        in: RoundedRectangle(
                            cornerRadius: DeAIDesign.controlRadius
                        )
                    )
                    .accessibilityLabel(L10n.t(.termPlaceholder, lang))

                if entry.kind == .replace {
                    Text("→").foregroundStyle(DeAIDesign.muted)
                    TextField(
                        L10n.t(.replacePlaceholder, lang),
                        text: Binding(
                            get: { entry.replacement ?? "" },
                            set: { entry.replacement = $0 }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(DeAIDesign.font(12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        DeAIDesign.sidebar,
                        in: RoundedRectangle(
                            cornerRadius: DeAIDesign.controlRadius
                        )
                    )
                    .accessibilityLabel(L10n.t(.replacePlaceholder, lang))
                }

                Picker(L10n.t(.matchLabel, lang), selection: $entry.match) {
                    ForEach(LexiconEntry.Match.allCases, id: \.self) { match in
                        Text(match.displayName(lang)).tag(match)
                    }
                }
                .labelsHidden()
                .frame(width: lang == .en ? 124 : 112)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(DeAIDesign.font(11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DeAIDesign.muted)
                .help(L10n.t(.deleteTooltip, lang))
                .accessibilityLabel(L10n.t(.deleteEntryA11y, lang))
            }
            if let error {
                Text(error)
                    .font(DeAIDesign.font(10))
                    .foregroundStyle(DeAIDesign.danger)
            }
        }
    }
}
