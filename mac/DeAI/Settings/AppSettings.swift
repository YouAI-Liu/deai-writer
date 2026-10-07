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

    /// Bundle ids where DeAI is disabled by default (browsers ship their own
    /// extension surface; terminals/Keychain/1Password are sensitive).
    public static let defaultDisabledApps: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.local.deai",
    ]

    /// Bundle ids where markdown residue checks default to off (editors that
    /// legitimately contain markdown source).
    public static let defaultMarkdownOffApps: Set<String> = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.Zed",
        "md.obsidian",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.t3tools.t3code",
    ]

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
        // New in the rewrite feature: optional in `Stored` so pre-upgrade
        // JSON keeps decoding (migration). First launch gets the OpenCode Go
        // preset as the active provider.
        let providers = stored?.providers ?? [ProviderConfig(preset: .opencodeGo)]
        self.providers = providers
        self.activeProviderId = stored?.activeProviderId
            ?? providers.first?.id
        self.rewriteHotkey = stored?.rewriteHotkey ?? .ctrlOptR
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
        // optional → old payloads (which lack these keys) still decode
        var providers: [ProviderConfig]?
        var activeProviderId: UUID?
        var rewriteHotkey: RewriteHotkey?
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
            providers: providers,
            activeProviderId: activeProviderId,
            rewriteHotkey: rewriteHotkey
        )
        if let data = try? JSONEncoder().encode(stored) {
            userDefaults.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: - per-app lookups

    /// Whether DeAI should run inside `bundleId` at all.
    public func isAppEnabled(_ bundleId: String) -> Bool {
        // never track ourselves — uses the live bundle id so Debug builds
        // (com.local.deai.debug) are excluded too
        if let own = Bundle.main.bundleIdentifier, bundleId == own { return false }
        if let rule = appRules[bundleId] { return rule.enabled }
        return !Self.defaultDisabledApps.contains(bundleId)
    }

    /// Whether markdown residue checks apply inside `bundleId`.
    public func markdownEnabled(for bundleId: String) -> Bool {
        if let rule = appRules[bundleId] { return rule.markdown }
        return !Self.defaultMarkdownOffApps.contains(bundleId)
    }

    /// Sorted rules for the settings list.
    public var sortedAppRules: [(key: String, value: AppRule)] {
        appRules.sorted { $0.key < $1.key }
    }

    public func setAppEnabled(_ bundleId: String, _ enabled: Bool) {
        var rule = appRules[bundleId] ?? AppRule(
            enabled: true,
            markdown: !Self.defaultMarkdownOffApps.contains(bundleId)
        )
        rule.enabled = enabled
        appRules[bundleId] = rule
    }

    public func checkOptions(for bundleId: String) -> CheckOptions {
        CheckOptions(
            grammar: grammar,
            aiToneEn: aiToneEn,
            aiToneZh: aiToneZh,
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
