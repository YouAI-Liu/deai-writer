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
        .onAppear { refreshKeyState() }
        .onReceive(hotkeyErrorPublisher) { hotkeyError = $0 }
        .onChange(of: settings.activeProviderId) { _ in refreshKeyState() }
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
                    Picker(
                        L10n.t(.formatLabel, lang),
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
                    .frame(width: 200)
                    Button(L10n.t(.saveButton, lang)) { saveKey() }
                        .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                        .disabled(keyDraft.isEmpty)
                    if keySaved && keyDraft.isEmpty {
                        Button(L10n.t(.clearButton, lang)) { clearKey() }
                            .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                    }
                    Text(keySaved ? L10n.t(.keySaved, lang) : L10n.t(.keyNotSet, lang))
                        .font(DeAIDesign.font(10))
                        .foregroundStyle(keySaved ? .green : DeAIDesign.muted)
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
            Picker(L10n.t(.modelLabel, lang), selection: modelSelection(p)) {
                ForEach(OpenCodeGoModels.all, id: \.self) { m in
                    Text(m).tag(m)
                }
                Text(L10n.t(.customModelTag, lang)).tag("__custom__")
            }
            .labelsHidden()
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

/// Personal lexicon + style notes. Entries persist to
/// `~/Library/Application Support/DeAI/lexicon.json` (watched for external
/// edits); the style text lives in `style.md` next to it.
private struct PersonalSettingsTab: View {
    @ObservedObject var lexicon: PersonalLexiconStore
    @Environment(\.deaiUILanguage) private var lang

    @State private var styleDraft = ""
    /// Debounce for style.md writes (keystroke → save after a pause).
    @State private var styleSaveTask: Task<Void, Never>?
    @State private var confirmResetStyle = false

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
                }
            }
            SettingsSection(L10n.t(.sectionStyle, lang)) {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $styleDraft)
                        .font(DeAIDesign.font(13))
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(height: 180)
                        .background(
                            DeAIDesign.sidebar,
                            in: RoundedRectangle(
                                cornerRadius: DeAIDesign.controlRadius
                            )
                        )
                        .accessibilityLabel(L10n.t(.styleA11y, lang))
                    HStack {
                        Text("\(styleDraft.count)/\(PersonalLexiconStore.maxStyleLength)")
                            .font(DeAIDesign.font(10).monospacedDigit())
                            .foregroundStyle(
                                styleDraft.count > PersonalLexiconStore.maxStyleLength
                                    ? DeAIDesign.danger : DeAIDesign.muted
                            )
                        Spacer()
                        Button(L10n.t(.restoreDefaults, lang)) { confirmResetStyle = true }
                            .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                        Button(L10n.t(.showInFinder, lang)) {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [lexicon.fileToReveal]
                            )
                        }
                        .buttonStyle(DeAIButtonStyle(secondary: true, compact: true))
                    }
                    Text(L10n.f(.styleCaption, lang, PersonalLexiconStore.maxStyleLength))
                        .font(DeAIDesign.font(10))
                        .foregroundStyle(DeAIDesign.muted)
                }
            }
        }
        .onAppear { styleDraft = lexicon.style }
        // external edits via the file watcher land in lexicon.style
        .onChange(of: lexicon.style) { _, new in
            if new != styleDraft { styleDraft = new }
        }
        .onChange(of: styleDraft) { _, new in
            styleSaveTask?.cancel()
            styleSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if lexicon.style != new { lexicon.setStyle(new) }
                }
            }
        }
        .confirmationDialog(
            L10n.t(.restoreStyleTitle, lang),
            isPresented: $confirmResetStyle,
            titleVisibility: .visible
        ) {
            Button(L10n.t(.restoreDefaults, lang), role: .destructive) {
                styleDraft = RewritePrompt.defaultStyle
                lexicon.setStyle(styleDraft)
            }
            Button(L10n.t(.cancelButton, lang), role: .cancel) {}
        } message: {
            Text(L10n.t(.restoreStyleMessage, lang))
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
