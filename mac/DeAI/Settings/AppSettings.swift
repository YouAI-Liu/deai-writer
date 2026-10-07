import Foundation

/// Per-app overrides: whether DeAI runs at all and whether markdown
/// residue checks apply.
public struct AppRule: Codable, Equatable {
    public var enabled: Bool
    public var markdown: Bool

    public init(enabled: Bool = true, markdown: Bool = true) {
        self.enabled = enabled
        self.markdown = markdown
    }
}

/// Persisted settings (`deai.settings.v1` in UserDefaults).
public final class AppSettings: ObservableObject {
    public static let defaultsKey = "deai.settings.v1"

    @Published public var autoUnderline: Bool {
        didSet { save() }
    }
    @Published public var grammar: Bool {
        didSet { save() }
    }
    @Published public var aiToneZh: Bool {
        didSet { save() }
    }
    @Published public var aiToneEn: Bool {
        didSet { save() }
    }
    @Published public var markdown: Bool {
        didSet { save() }
    }
    /// 1 = 严格, 2 = 标准, 3 = 敏感.
    @Published public var sensitivity: Int {
        didSet {
            if !(1...3).contains(sensitivity) { sensitivity = 2 }
            save()
        }
    }
    /// Rule ids the user has permanently disabled.
    @Published public var disabledRuleIds: Set<String> {
        didSet { save() }
    }
    /// Per-bundle-id overrides.
    @Published public var appRules: [String: AppRule] {
        didSet { save() }
    }
    /// Underline appearance (color/shape per category + global knobs).
    @Published public var underline: UnderlineAppearance {
        didSet { save() }
    }
    /// Per-应用类型 rules; missing groups fall back to `AppGroup.defaultRule`.
    @Published public var groupRules: [AppGroup: GroupRule] {
        didSet { save() }
    }

    /// AI-rewrite providers; the selected one is `activeProviderId`.
    /// (internal: ProviderConfig/SecretStore are app-internal types)
    @Published var providers: [ProviderConfig] {
        didSet { save() }
    }
    @Published var activeProviderId: UUID? {
        didSet { save() }
    }
    /// Global hotkey that triggers a rewrite of the current scope.
    @Published var rewriteHotkey: RewriteHotkey {
        didSet { save() }
    }

    /// API keys live in the keychain, keyed by provider UUID — never in
    /// UserDefaults, never logged.
    let secrets: SecretStore

    /// Session-scoped ignores: `(ruleId, matchedText)` pairs — cleared on
    /// relaunch, intentionally not persisted.
    @Published public var sessionIgnored: Set<IgnoreKey> = []

    public struct IgnoreKey: Hashable {
        public let ruleId: String
        public let text: String
        public init(ruleId: String, text: String) {
            self.ruleId = ruleId
            self.text = text
        }
    }

    init(
        userDefaults: UserDefaults = .standard,
        secrets: SecretStore = KeychainSecretStore()
    ) {
        var stored: Stored?
        if let data = userDefaults.data(forKey: Self.defaultsKey) {
            stored = try? JSONDecoder().decode(Stored.self, from: data)
        }
        self.autoUnderline = stored?.autoUnderline ?? true
        self.grammar = stored?.grammar ?? true
        self.aiToneZh = stored?.aiToneZh ?? true
        self.aiToneEn = stored?.aiToneEn ?? true
        self.markdown = stored?.markdown ?? true
        self.sensitivity = stored?.sensitivity ?? 2
        self.disabledRuleIds = stored?.disabledRuleIds ?? []
        self.appRules = stored?.appRules ?? [:]
        self.underline = stored?.underline ?? .default
        var rules = AppGroup.defaultRules
        if let storedRules = stored?.groupRules {
            for (key, rule) in storedRules {
                if let group = AppGroup(rawValue: key) { rules[group] = rule }
            }
        }
        self.groupRules = rules
        // New in the rewrite feature: optional in `Stored` so pre-upgrade
        // JSON keeps decoding (migration). First launch gets the OpenCode Go
        // preset as the active provider.
        let providers = stored?.providers ?? [ProviderConfig(preset: .opencodeGo)]
        self.providers = providers
        self.activeProviderId = stored?.activeProviderId
            ?? providers.first?.id
        self.rewriteHotkey = stored?.rewriteHotkey ?? .default
        self.userDefaults = userDefaults
        self.secrets = secrets
    }

    private let userDefaults: UserDefaults

    private struct Stored: Codable {
        var autoUnderline: Bool
        var grammar: Bool
        var aiToneZh: Bool
        var aiToneEn: Bool
        var markdown: Bool
        var sensitivity: Int
        var disabledRuleIds: Set<String>
        var appRules: [String: AppRule]
        var underline: UnderlineAppearance
        /// JSON object keyed by `AppGroup.rawValue` (Swift encodes
        /// enum-keyed dictionaries as arrays — keep a stable shape).
        var groupRules: [String: GroupRule]
        // optional → old payloads (which lack these keys) still decode
        var providers: [ProviderConfig]?
        var activeProviderId: UUID?
        var rewriteHotkey: RewriteHotkey?

        init(
            autoUnderline: Bool, grammar: Bool, aiToneZh: Bool,
            aiToneEn: Bool, markdown: Bool, sensitivity: Int,
            disabledRuleIds: Set<String>, appRules: [String: AppRule],
            underline: UnderlineAppearance, groupRules: [String: GroupRule],
            providers: [ProviderConfig]?, activeProviderId: UUID?,
            rewriteHotkey: RewriteHotkey?
        ) {
            self.autoUnderline = autoUnderline
            self.grammar = grammar
            self.aiToneZh = aiToneZh
            self.aiToneEn = aiToneEn
            self.markdown = markdown
            self.sensitivity = sensitivity
            self.disabledRuleIds = disabledRuleIds
            self.appRules = appRules
            self.underline = underline
            self.groupRules = groupRules
            self.providers = providers
            self.activeProviderId = activeProviderId
            self.rewriteHotkey = rewriteHotkey
        }

        /// Tolerant decode: settings written by older builds (which lack the
        /// newer keys) must load instead of failing wholesale.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            autoUnderline = try c.decodeIfPresent(Bool.self, forKey: .autoUnderline) ?? true
            grammar = try c.decodeIfPresent(Bool.self, forKey: .grammar) ?? true
            aiToneZh = try c.decodeIfPresent(Bool.self, forKey: .aiToneZh) ?? true
            aiToneEn = try c.decodeIfPresent(Bool.self, forKey: .aiToneEn) ?? true
            markdown = try c.decodeIfPresent(Bool.self, forKey: .markdown) ?? true
            sensitivity = try c.decodeIfPresent(Int.self, forKey: .sensitivity) ?? 2
            disabledRuleIds = try c.decodeIfPresent(Set<String>.self, forKey: .disabledRuleIds) ?? []
            appRules = try c.decodeIfPresent([String: AppRule].self, forKey: .appRules) ?? [:]
            underline = try c.decodeIfPresent(UnderlineAppearance.self, forKey: .underline) ?? .default
            groupRules = try c.decodeIfPresent([String: GroupRule].self, forKey: .groupRules) ?? [:]
            providers = try c.decodeIfPresent([ProviderConfig].self, forKey: .providers)
            activeProviderId = try c.decodeIfPresent(UUID.self, forKey: .activeProviderId)
            rewriteHotkey = try c.decodeIfPresent(RewriteHotkey.self, forKey: .rewriteHotkey)
        }
    }

    private func save() {
        let stored = Stored(
            autoUnderline: autoUnderline,
            grammar: grammar,
            aiToneZh: aiToneZh,
            aiToneEn: aiToneEn,
            markdown: markdown,
            sensitivity: sensitivity,
            disabledRuleIds: disabledRuleIds,
            appRules: appRules,
            underline: underline,
            groupRules: Dictionary(
                uniqueKeysWithValues: groupRules.map { ($0.key.rawValue, $0.value) }
            ),
            providers: providers,
            activeProviderId: activeProviderId,
            rewriteHotkey: rewriteHotkey
        )
        if let data = try? JSONEncoder().encode(stored) {
            userDefaults.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: - group + per-app lookups

    /// The effective rule for `bundleId`'s group (defaults when unset).
    public func groupRule(for bundleId: String) -> GroupRule {
        let group = AppGroup.group(for: bundleId)
        return groupRules[group] ?? AppGroup.defaultRule(for: group)
    }

    /// Whether DeAI should run inside `bundleId` at all.
    public func isAppEnabled(_ bundleId: String) -> Bool {
        // never track ourselves — uses the live bundle id so Debug builds
        // (com.local.deai.debug) are excluded too, plus the whole
        // com.local.deai[.*] family so Debug and Release builds ignore
        // each other (replacing the old defaultDisabledApps entry)
        if let own = Bundle.main.bundleIdentifier, bundleId == own { return false }
        if bundleId == "com.local.deai" || bundleId.hasPrefix("com.local.deai.") {
            return false
        }
        if let rule = appRules[bundleId] { return rule.enabled }
        return groupRule(for: bundleId).enabled
    }

    /// Whether check `kind` may run inside `bundleId`: the group's check set
    /// gates everything; for markdown a per-app `AppRule.markdown` can only
    /// narrow further (never re-enable a check the group turned off).
    public func isCheckEnabled(_ kind: CheckKind, for bundleId: String) -> Bool {
        guard groupRule(for: bundleId).checks.contains(kind) else { return false }
        if kind == .markdown, let rule = appRules[bundleId], !rule.markdown {
            return false
        }
        return true
    }

    /// Whether markdown residue checks apply inside `bundleId`.
    public func markdownEnabled(for bundleId: String) -> Bool {
        isCheckEnabled(.markdown, for: bundleId)
    }

    /// Sorted rules for the settings list.
    public var sortedAppRules: [(key: String, value: AppRule)] {
        appRules.sorted { $0.key < $1.key }
    }

    /// A fresh per-app rule for `bundleId`, with markdown defaulting to the
    /// group's markdown check.
    public func defaultAppRule(for bundleId: String) -> AppRule {
        AppRule(
            enabled: true,
            markdown: groupRule(for: bundleId).checks.contains(.markdown)
        )
    }

    public func setAppEnabled(_ bundleId: String, _ enabled: Bool) {
        var rule = appRules[bundleId] ?? defaultAppRule(for: bundleId)
        rule.enabled = enabled
        appRules[bundleId] = rule
    }

    public func checkOptions(for bundleId: String) -> CheckOptions {
        CheckOptions(
            grammar: grammar && isCheckEnabled(.grammar, for: bundleId),
            aiToneEn: aiToneEn && isCheckEnabled(.aiToneEn, for: bundleId),
            aiToneZh: aiToneZh && isCheckEnabled(.aiToneZh, for: bundleId),
            markdown: markdown && markdownEnabled(for: bundleId),
            sensitivity: UInt8(clamping: sensitivity)
        )
    }

    // MARK: - AI providers

    /// The provider rewrite requests go to. Falls back to the first entry
    /// when `activeProviderId` points at a deleted row.
    var activeProvider: ProviderConfig? {
        providers.first(where: { $0.id == activeProviderId })
            ?? providers.first
    }

    @discardableResult
    func addProvider(preset: ProviderPreset) -> ProviderConfig {
        let p = ProviderConfig(preset: preset)
        providers.append(p)
        activeProviderId = p.id
        return p
    }

    func deleteProvider(id: UUID) {
        providers.removeAll { $0.id == id }
        secrets.set(nil, for: id.uuidString)
        if activeProviderId == id {
            activeProviderId = providers.first?.id
        }
    }

    func updateProvider(_ provider: ProviderConfig) {
        guard let i = providers.firstIndex(where: { $0.id == provider.id })
        else { return }
        providers[i] = provider
    }
}
