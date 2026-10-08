import Foundation

/// 应用类型: a coarse grouping of bundle ids so a whole class of apps can be
/// enabled/tuned at once. Per-app `AppRule`s still override the group.
public enum AppGroup: String, Codable, CaseIterable {
    case browser
    case office
    case notes
    case communication
    case code
    case sensitive
    case other

    public func displayName(_ lang: UILanguage) -> String {
        let key: L10n.Key = switch self {
        case .browser: .groupBrowser
        case .office: .groupOffice
        case .notes: .groupNotes
        case .communication: .groupCommunication
        case .code: .groupCode
        case .sensitive: .groupSensitive
        case .other: .groupOther
        }
        return L10n.t(key, lang)
    }

    /// Example apps shown as a caption in settings — the list connector is
    /// localized, the app names themselves are not.
    public func examples(_ lang: UILanguage) -> String {
        let key: L10n.Key = switch self {
        case .browser: .examplesBrowser
        case .office: .examplesOffice
        case .notes: .examplesNotes
        case .communication: .examplesCommunication
        case .code: .examplesCode
        case .sensitive: .examplesSensitive
        case .other: .examplesOther
        }
        return L10n.t(key, lang)
    }
}

/// The check categories, used for per-group check selection.
public enum CheckKind: String, Codable, CaseIterable {
    case grammar
    case aiToneZh
    case aiToneEn
    case markdown
    case personal

    public func shortName(_ lang: UILanguage) -> String {
        let key: L10n.Key = switch self {
        case .grammar: .kindGrammar
        case .aiToneZh: .kindAIToneZh
        case .aiToneEn: .kindAIToneEn
        case .markdown: .kindMarkdown
        case .personal: .kindPersonal
        }
        return L10n.t(key, lang)
    }
}

/// Per-group switch: whether DeAI serves the group and which checks run.
public struct GroupRule: Codable, Equatable {
    public var enabled: Bool
    public var checks: Set<CheckKind>

    public init(enabled: Bool, checks: Set<CheckKind>) {
        self.enabled = enabled
        self.checks = checks
    }
}

public extension AppGroup {
    /// Groups the user may toggle. `.sensitive` is a hard exclusion list —
    /// terminals, password managers and DeAI itself are never served, so it
    /// is hidden from every UI and `isAppEnabled` always returns false for
    /// it regardless of saved group rules or per-app overrides.
    static var configurable: [AppGroup] {
        allCases.filter { $0 != .sensitive }
    }

    /// Defaults: browsers are covered by the Chrome extension and
    /// terminals/password managers are sensitive — both start disabled.
    /// Code editors skip the markdown-residue check (they legitimately hold
    /// markdown source); every other group runs all four checks.
    static func defaultRule(for group: AppGroup) -> GroupRule {
        switch group {
        case .browser, .sensitive:
            return GroupRule(enabled: false, checks: Set(CheckKind.allCases))
        case .code:
            return GroupRule(enabled: true, checks: Set(CheckKind.allCases).subtracting([.markdown]))
        case .office, .notes, .communication, .other:
            return GroupRule(enabled: true, checks: Set(CheckKind.allCases))
        }
    }

    static var defaultRules: [AppGroup: GroupRule] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, defaultRule(for: $0)) })
    }

    /// Bundle-id → group lookup. Unknown apps land in `.other`.
    static func group(for bundleId: String) -> AppGroup {
        if bundleId.hasPrefix("com.jetbrains.") { return .code }
        return table[bundleId] ?? .other
    }

    private static let table: [String: AppGroup] = [
        // 浏览器
        "com.apple.Safari": .browser,
        "com.apple.SafariTechnologyPreview": .browser,
        "com.google.Chrome": .browser,
        "com.google.Chrome.canary": .browser,
        "com.google.Chrome.beta": .browser,
        "com.google.Chrome.dev": .browser,
        "com.brave.Browser": .browser,
        "com.microsoft.edgemac": .browser,
        "com.microsoft.edgemac.Canary": .browser,
        "com.microsoft.edgemac.Dev": .browser,
        "com.microsoft.edgemac.Beta": .browser,
        "company.thebrowser.Browser": .browser, // Arc
        "org.mozilla.firefox": .browser,
        "com.operasoftware.Opera": .browser,
        "com.vivaldi.Vivaldi": .browser,
        "com.duckduckgo.macos.browser": .browser,
        // Office 与文档
        "com.microsoft.Word": .office,
        "com.microsoft.Excel": .office,
        "com.microsoft.Powerpoint": .office,
        "com.apple.iWork.Pages": .office,
        "com.apple.iWork.Numbers": .office,
        "com.apple.iWork.Keynote": .office,
        "com.kingsoft.wpsoffice.mac": .office, // WPS
        // 笔记
        "com.apple.Notes": .notes,
        "md.obsidian": .notes,
        "notion.id": .notes,
        "com.bear-writer.BearMac": .notes,
        "com.apple.TextEdit": .notes,
        // 聊天与邮件
        "com.apple.mail": .communication,
        "com.microsoft.Outlook": .communication,
        "com.tinyspeck.slackmacgap": .communication, // Slack
        "com.tencent.xinWeChat": .communication, // WeChat
        "com.electron.lark": .communication, // Lark/Feishu
        "com.bytedance.lark.mac": .communication, // Feishu
        "com.alibaba.DingTalkMac": .communication,
        "com.alibabagroup.dingtalk": .communication,
        "ru.keepcoder.Telegram": .communication,
        "com.apple.MobileSMS": .communication, // Messages
        "com.tencent.qq": .communication,
        // 代码编辑器
        "com.microsoft.VSCode": .code,
        "com.todesktop.230313mzl4w4u92": .code, // Cursor
        "dev.zed.Zed": .code,
        "com.apple.dt.Xcode": .code,
        "com.sublimetext.4": .code,
        "com.t3tools.t3code": .code, // T3 Code
        // 终端与密码 (sensitive)
        "com.apple.Terminal": .sensitive,
        "com.googlecode.iterm2": .sensitive,
        "dev.warp.Warp-Stable": .sensitive,
        "com.mitchellh.ghostty": .sensitive,
        "com.apple.keychainaccess": .sensitive,
        "com.1password.1password": .sensitive,
        "com.agilebits.onepassword7": .sensitive,
        // never underline ourselves, whichever bundle id the build uses
        "com.local.deai": .sensitive,
        "com.local.deai.debug": .sensitive,
    ]
}
