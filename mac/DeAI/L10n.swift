import SwiftUI

/// UI language — 中文 or English only. Persisted in `deai.settings.v1`;
/// a fresh install follows `Locale.preferredLanguages` (zh when the first
/// preferred language starts with "zh", en otherwise).
public enum UILanguage: String, Codable, CaseIterable {
    case zh
    case en

    /// Fresh-install default: only relevant when there is no stored
    /// settings payload at all (old payloads decode `uiLanguage` as `.zh`).
    static var systemDefault: UILanguage {
        (Locale.preferredLanguages.first ?? "")
            .hasPrefix("zh") ? .zh : .en
    }
}

/// Every user-visible string lives in this one typed table so the two
/// language columns are easy to audit. Keys are an enum: a missing table
/// entry is caught by `L10nTests.testAllKeysHaveBothLanguages` (which also
/// asserts no CJK leaks into the English column).
///
/// Interpolated strings use `String(format:)` placeholders (%@, %d) —
/// zh uses the fullwidth colon "：" before a value, en uses ": ".
enum L10n {
    enum Key: String, CaseIterable {
        // settings tabs
        case tabCheck
        case tabUnderline
        case tabAI
        case tabPersonal
        // check tab
        case languageRow
        case sectionCategories
        case catGrammar
        case catAIToneZh
        case catAIToneEn
        case catMarkdown
        case catPersonal
        case sectionSensitivity
        case sensStrict
        case sensStandard
        case sensSensitive
        case sensitivityLabel
        case sectionAppGroups
        case toggleEnabled
        case sectionAppExceptions
        case ruleEnabled
        case ruleEnabledNoMarkdown
        case ruleDisabled
        case deleteTooltip
        case removeAppA11y      // %@ bundle id
        case bundlePlaceholder
        case bundleIdA11y
        case addButton
        case addCurrentApp
        case sectionDisabledRules
        case noDisabledRules
        case reenableButton
        // app groups (names + example lists; app names stay untranslated)
        case groupBrowser
        case groupOffice
        case groupNotes
        case groupCommunication
        case groupCode
        case groupSensitive
        case groupOther
        case examplesBrowser
        case examplesOffice
        case examplesNotes
        case examplesCommunication
        case examplesCode
        case examplesSensitive
        case examplesOther
        // check-kind chips
        case kindGrammar
        case kindAIToneZh
        case kindAIToneEn
        case kindMarkdown
        case kindPersonal
        // underline tab
        case sectionPreview
        case sectionCategoryStyles
        case followTheme
        case colorLabel
        case shapeLabel
        case shapeStraight
        case shapeWavy
        case shapeDashed
        case shapeDotted
        case sectionGlobal
        case thicknessLabel
        case opacityLabel
        case offsetLabel
        case dimLowConfidence
        case highlightFill
        case restoreDefaults
        case previewLine1
        case previewLine2
        // category display names (card tag + underline rows)
        case catNameGrammar
        case catNameAIToneZh
        case catNameAIToneEn
        case catNameMarkdown
        case catNamePersonal
        // AI tab
        case sectionProviders
        case addProvider
        case providerCustom
        case configSection     // %@ provider name
        case nameLabel
        case formatLabel
        case modelLabel
        case modelIdPlaceholder
        case customModelTag
        case customModelLabel
        case saveButton
        case clearButton
        case keySaved
        case keyNotSet
        case testConnection
        case testing
        case testSucceeded     // %d ms
        case sectionShortcut
        case shortcutLabel
        case shortcutCaption
        case recordPrompt
        case clickToRecord
        case clearShortcut
        case needModifier
        case reservedCombo
        case recorderA11y
        case hotkeyNotSet
        // personal tab (词库)
        case sectionLexicon
        case addEntry
        case lexiconCaption
        case lexiconSharedNote
        case cancelButton
        case showInFinder
        case kindLabel
        case termPlaceholder
        case replacePlaceholder
        case matchLabel
        case deleteEntryA11y
        case lexiconKindReplace
        case lexiconKindAvoid
        case lexiconKindKeep
        case matchExact
        case matchCaseInsensitive
        case matchWholeWord
        case errEmptyTerm
        case errTermTooLong    // %d max chars
        case errDuplicate
        // rewrite skills (AI tab section)
        case sectionSkills
        case safetyDisclosure
        case skillForZh
        case skillForEn
        case skillImport
        case skillBuiltinName
        case migratedSkillName
        case skillLangZh
        case skillLangEn
        case skillLangAny
        case skillSize          // %d chars, ~%d tokens
        case skillLongWarning
        case skillViewEdit
        case skillDuplicate
        case builtinReadonlyNote
        case skillDeleteTitle   // %@ skill name
        case skillDeleteMessage
        case skillTooLarge      // %d actual, %d max
        case skillNotMarkdown
        case skillUnreadable
        case skillDeleted
        case skillNameLabel
        case skillDescLabel
        case skillBodyLabel
        case skillLanguageLabel
        // menu-bar panel
        case menuAutoUnderline
        case menuCheckInApp    // %@ app name
        case menuAppGroups
        case menuSettings
        case menuRuleTest
        case menuUIPreview
        case menuQuit
        // suggestion card
        case stepperPrev
        case stepperNext
        case stepperA11y       // %d of %d
        case closeTooltip
        case dismissA11y
        case replaceWithA11y   // %@ suggestion
        case deleteRow
        case deleteTextA11y
        case applyLabel
        case rewriteA11y
        case rewriteTooltip
        case rewriteSelectionTooltip
        case ignoreLabel
        case editEntry
        case addKeepEntry
        case rememberFix
        case disableRule
        case moreLabel
        case emptyTag
        case emptyBody
        case emptyFlash
        case recheckButton
        case appliedLabel
        case applyFailedLabel
        // rewrite panel
        case rewriteTitle
        case rewriting
        case originalLabel
        case rewriteLabel
        case replaceButton
        case copyButton
        case retryButton
        case openSettings
        case noChange
        case rememberToggle    // %d pairs
        case rememberSaved
        case rememberA11y
        case pairDelete        // %@ deleted text
        case pairReplace       // %@ from, %@ to
        case addToLexicon
        // rewrite errors (LLMClient + controller)
        case errorTooLong      // %d max chars
        case errorConfigureAI
        case errorReadText
        case errorOriginalChanged
        case errorInvalidBaseURL // %@ url
        case errorHTTPAuth
        case errorHTTPRate
        case errorParseResponse
        case errorNoText
        case hotkeyTaken
        case hotkeyFailed      // %d status
        // permission window
        case permissionTitle
        case permissionBody
        case permissionNote
        case openSystemSettings
        // rule-test window (ContentView)
        case ruleTestTitle
        case findingsCount     // %d findings
        case stripMarkdown
        case originalPrefix    // %@ excerpt
        case suggestionsPrefix // %@ joined suggestions
        // window titles
        case windowSettings
        case windowPermission
        case windowRuleTest
        // toggle accessibility
        case turnOff
        case turnOn
        case valueOn
        case valueOff
        // personal rule explanations (%@ matched / %@ replacement)
        case personalReplaceMessage
        case personalAvoidMessage
    }

    // swift-format does not run on this table — keep one key per line and
    // zh/en columns aligned for review.
    static let zh: [Key: String] = [
        .tabCheck: "检查",
        .tabUnderline: "下划线外观",
        .tabAI: "AI 改写",
        .tabPersonal: "词库",

        .languageRow: "语言 / Language",
        .sectionCategories: "检查类别",
        .catGrammar: "语法 (Grammar)",
        .catAIToneZh: "中文 AI 腔",
        .catAIToneEn: "英文 AI 腔",
        .catMarkdown: "Markdown 残留",
        .catPersonal: "个人词库",
        .sectionSensitivity: "敏感度",
        .sensStrict: "严格",
        .sensStandard: "标准",
        .sensSensitive: "敏感",
        .sensitivityLabel: "敏感度",
        .sectionAppGroups: "应用类型",
        .toggleEnabled: "启用",
        .sectionAppExceptions: "单个应用例外",
        .ruleEnabled: "启用",
        .ruleEnabledNoMarkdown: "启用(不含 Markdown)",
        .ruleDisabled: "停用",
        .deleteTooltip: "删除",
        .removeAppA11y: "移除 %@",
        .bundlePlaceholder: "bundle id (例如 com.apple.TextEdit)",
        .bundleIdA11y: "应用 Bundle ID",
        .addButton: "添加",
        .addCurrentApp: "添加当前应用",
        .sectionDisabledRules: "已停用规则",
        .noDisabledRules: "无已停用规则",
        .reenableButton: "重新启用",

        .groupBrowser: "浏览器",
        .groupOffice: "Office 与文档",
        .groupNotes: "笔记",
        .groupCommunication: "聊天与邮件",
        .groupCode: "代码编辑器",
        .groupSensitive: "终端与密码",
        .groupOther: "其他",
        .examplesBrowser: "Safari、Chrome、Arc、Firefox",
        .examplesOffice: "Word、Pages、WPS、Excel、Keynote",
        .examplesNotes: "备忘录、Obsidian、Notion、Bear、文本编辑",
        .examplesCommunication: "邮件、微信、Slack、飞书、钉钉",
        .examplesCode: "VSCode、Cursor、Zed、Xcode、JetBrains",
        .examplesSensitive: "终端、iTerm2、Warp、钥匙串、1Password",
        .examplesOther: "未归类的应用",

        .kindGrammar: "语法",
        .kindAIToneZh: "中文",
        .kindAIToneEn: "英文",
        .kindMarkdown: "MD",
        .kindPersonal: "个人",

        .sectionPreview: "预览",
        .sectionCategoryStyles: "分类样式",
        .followTheme: "跟随主题",
        .colorLabel: "颜色",
        .shapeLabel: "线型",
        .shapeStraight: "直线",
        .shapeWavy: "波浪线",
        .shapeDashed: "虚线",
        .shapeDotted: "点线",
        .sectionGlobal: "全局",
        .thicknessLabel: "粗细",
        .opacityLabel: "不透明度",
        .offsetLabel: "距离",
        .dimLowConfidence: "低置信度显示为虚线",
        .highlightFill: "背景高亮",
        .restoreDefaults: "恢复默认",
        .previewLine1: "这是一个示例句子 sample text",
        .previewLine2: "低置信度示例 low confidence",

        .catNameGrammar: "语法",
        .catNameAIToneZh: "中文 AI 腔",
        .catNameAIToneEn: "英文 AI 腔",
        .catNameMarkdown: "Markdown 残留",
        .catNamePersonal: "个人偏好",

        .sectionProviders: "服务",
        .addProvider: "添加服务…",
        .providerCustom: "自定义",
        .configSection: "配置 — %@",
        .nameLabel: "名称",
        .formatLabel: "接口格式",
        .modelLabel: "模型",
        .modelIdPlaceholder: "模型 id",
        .customModelTag: "自定义…",
        .customModelLabel: "自定义模型",
        .saveButton: "保存",
        .clearButton: "清除",
        .keySaved: "已保存 ✓",
        .keyNotSet: "未设置",
        .testConnection: "测试连接",
        .testing: "测试中…",
        .testSucceeded: "✓ 连接成功 (%d ms)",
        .sectionShortcut: "快捷键",
        .shortcutLabel: "选中检查快捷键",
        .shortcutCaption: "选中文字后按下：检查并给出建议；无选中时检查光标所在段落",
        .recordPrompt: "请按下快捷键…",
        .clickToRecord: "点击录制",
        .clearShortcut: "清除快捷键",
        .needModifier: "需要包含 ⌃、⌥ 或 ⌘",
        .reservedCombo: "这个组合被系统或常用操作占用",
        .recorderA11y: "选中检查快捷键",
        .hotkeyNotSet: "未设置",

        .sectionLexicon: "词库",
        .addEntry: "添加词条",
        .lexiconCaption: "替换与避免会产生个人偏好下划线；保留词会盖住同位置的其他提示。",
        .lexiconSharedNote: "词库同时用于本地检查和 AI 改写。",
        .cancelButton: "取消",
        .showInFinder: "在 Finder 中显示",
        .kindLabel: "类型",
        .termPlaceholder: "原词",
        .replacePlaceholder: "替换为",
        .matchLabel: "匹配",
        .deleteEntryA11y: "删除词条",
        .lexiconKindReplace: "替换",
        .lexiconKindAvoid: "避免",
        .lexiconKindKeep: "保留",
        .matchExact: "精确",
        .matchCaseInsensitive: "忽略大小写",
        .matchWholeWord: "整词",
        .errEmptyTerm: "词条不能为空",
        .errTermTooLong: "词条最长 %d 字",
        .errDuplicate: "重复的词条",

        .sectionSkills: "改写技能",
        .safetyDisclosure: "安全规则（固定，不可修改）",
        .skillForZh: "中文文本使用",
        .skillForEn: "英文文本使用",
        .skillImport: "导入技能…",
        .skillBuiltinName: "去 AI 味（默认）",
        .migratedSkillName: "我的风格（已迁移）",
        .skillLangZh: "中文",
        .skillLangEn: "英文",
        .skillLangAny: "通用",
        .skillSize: "%d 字 · 约 %d tokens",
        .skillLongWarning: "较长：每次改写会更慢、更贵",
        .skillViewEdit: "查看/编辑",
        .skillDuplicate: "复制为新技能",
        .builtinReadonlyNote: "内置技能为只读",
        .skillDeleteTitle: "删除技能「%@」？",
        .skillDeleteMessage: "该技能文件将从磁盘中删除。",
        .skillTooLarge: "技能正文 %d 字，超过上限 %d 字",
        .skillNotMarkdown: "请选择 .md 文件或包含 SKILL.md 的文件夹",
        .skillUnreadable: "无法读取所选文件",
        .skillDeleted: "该技能已不存在，无法保存",
        .skillNameLabel: "名称",
        .skillDescLabel: "描述",
        .skillBodyLabel: "正文",
        .skillLanguageLabel: "语言",

        .menuAutoUnderline: "自动下划线",
        .menuCheckInApp: "在 %@ 中检查",
        .menuAppGroups: "应用类型",
        .menuSettings: "设置",
        .menuRuleTest: "规则测试窗口",
        .menuUIPreview: "UI 预览",
        .menuQuit: "退出 DeAI",

        .stepperPrev: "上一个",
        .stepperNext: "下一个",
        .stepperA11y: "第 %d 个，共 %d 个",
        .closeTooltip: "关闭",
        .dismissA11y: "关闭建议",
        .replaceWithA11y: "替换为：%@",
        .deleteRow: "删除",
        .deleteTextA11y: "删除这段文字",
        .applyLabel: "应用",
        .rewriteA11y: "AI 改写",
        .rewriteTooltip: "AI 改写这一段",
        .rewriteSelectionTooltip: "AI 改写选中内容",
        .ignoreLabel: "忽略",
        .editEntry: "编辑词条…",
        .addKeepEntry: "加入保留词",
        .rememberFix: "记住此改法",
        .disableRule: "停用此规则",
        .moreLabel: "更多",
        .emptyTag: "检查完成",
        .emptyBody: "未发现问题",
        .emptyFlash: "仍未发现问题",
        .recheckButton: "重新检测",
        .appliedLabel: "已应用",
        .applyFailedLabel: "未能应用",

        .rewriteTitle: "AI 改写",
        .rewriting: "AI 改写中…",
        .originalLabel: "原文",
        .rewriteLabel: "改写",
        .replaceButton: "替换",
        .copyButton: "复制",
        .retryButton: "重试",
        .openSettings: "打开设置",
        .noChange: "没有需要修改的地方",
        .rememberToggle: "记住改法（%d）",
        .rememberSaved: "已加入词库",
        .rememberA11y: "记住改法",
        .pairDelete: "删除「%@」",
        .pairReplace: "「%@」→「%@」",
        .addToLexicon: "加入词库",

        .errorTooLong: "选中内容过长（上限 %d 字）",
        .errorConfigureAI: "请先在设置中配置 AI 服务",
        .errorReadText: "无法读取文本",
        .errorOriginalChanged: "原文已改动，请重新改写",
        .errorInvalidBaseURL: "无效的 Base URL：%@",
        .errorHTTPAuth: "API Key 无效或未授权",
        .errorHTTPRate: "请求过于频繁或额度已用完",
        .errorParseResponse: "无法解析响应",
        .errorNoText: "响应中没有文本内容",
        .hotkeyTaken: "该快捷键已被其他应用占用，请换一个",
        .hotkeyFailed: "快捷键注册失败（错误 %d）",

        .permissionTitle: "辅助功能权限",
        .permissionBody: "DeAI 需要读取前台文本，以标出语法、AI 腔和 Markdown 残留；密码等安全输入框会跳过。",
        .permissionNote: "在辅助功能列表中勾选 DeAI，授权后此窗口会自动关闭。",
        .openSystemSettings: "打开系统设置",

        .ruleTestTitle: "规则测试",
        .findingsCount: "%d 条提示",
        .stripMarkdown: "清除 Markdown",
        .originalPrefix: "原文：%@",
        .suggestionsPrefix: "建议：%@",

        .windowSettings: "DeAI 设置",
        .windowPermission: "DeAI — 辅助功能权限",
        .windowRuleTest: "调试：规则测试窗口",

        .turnOff: "关闭",
        .turnOn: "开启",
        .valueOn: "已开启",
        .valueOff: "已关闭",

        .personalReplaceMessage: "个人偏好：用「%@」代替「%@」",
        .personalAvoidMessage: "个人偏好：避免使用「%@」",
    ]

    static let en: [Key: String] = [
        .tabCheck: "Check",
        .tabUnderline: "Underlines",
        .tabAI: "AI Rewrite",
        .tabPersonal: "Lexicon",

        .languageRow: "语言 / Language",
        .sectionCategories: "Categories",
        .catGrammar: "Grammar",
        .catAIToneZh: "Chinese AI tone",
        .catAIToneEn: "English AI tone",
        .catMarkdown: "Markdown residue",
        .catPersonal: "Personal lexicon",
        .sectionSensitivity: "Sensitivity",
        .sensStrict: "Strict",
        .sensStandard: "Standard",
        .sensSensitive: "Sensitive",
        .sensitivityLabel: "Sensitivity",
        .sectionAppGroups: "App types",
        .toggleEnabled: "Enabled",
        .sectionAppExceptions: "Per-app exceptions",
        .ruleEnabled: "Enabled",
        .ruleEnabledNoMarkdown: "Enabled (no Markdown)",
        .ruleDisabled: "Disabled",
        .deleteTooltip: "Delete",
        .removeAppA11y: "Remove %@",
        .bundlePlaceholder: "bundle id (e.g. com.apple.TextEdit)",
        .bundleIdA11y: "App bundle ID",
        .addButton: "Add",
        .addCurrentApp: "Add current app",
        .sectionDisabledRules: "Disabled rules",
        .noDisabledRules: "No disabled rules",
        .reenableButton: "Re-enable",

        .groupBrowser: "Browsers",
        .groupOffice: "Office & documents",
        .groupNotes: "Notes",
        .groupCommunication: "Chat & mail",
        .groupCode: "Code editors",
        .groupSensitive: "Terminals & passwords",
        .groupOther: "Other",
        .examplesBrowser: "Safari, Chrome, Arc, Firefox",
        .examplesOffice: "Word, Pages, WPS, Excel, Keynote",
        .examplesNotes: "Notes, Obsidian, Notion, Bear, TextEdit",
        .examplesCommunication: "Mail, WeChat, Slack, Lark, DingTalk",
        .examplesCode: "VSCode, Cursor, Zed, Xcode, JetBrains",
        .examplesSensitive: "Terminal, iTerm2, Warp, Keychain Access, 1Password",
        .examplesOther: "Uncategorized apps",

        .kindGrammar: "Grammar",
        .kindAIToneZh: "Chinese",
        .kindAIToneEn: "English",
        .kindMarkdown: "MD",
        .kindPersonal: "Personal",

        .sectionPreview: "Preview",
        .sectionCategoryStyles: "Category styles",
        .followTheme: "Follow theme",
        .colorLabel: "Color",
        .shapeLabel: "Style",
        .shapeStraight: "Straight",
        .shapeWavy: "Wavy",
        .shapeDashed: "Dashed",
        .shapeDotted: "Dotted",
        .sectionGlobal: "Global",
        .thicknessLabel: "Thickness",
        .opacityLabel: "Opacity",
        .offsetLabel: "Offset",
        .dimLowConfidence: "Low-confidence shown dashed",
        .highlightFill: "Background highlight",
        .restoreDefaults: "Restore Defaults",
        .previewLine1: "This is a sample sentence",
        .previewLine2: "Low-confidence sample text",

        .catNameGrammar: "Grammar",
        .catNameAIToneZh: "Chinese AI tone",
        .catNameAIToneEn: "English AI tone",
        .catNameMarkdown: "Markdown",
        .catNamePersonal: "Personal",

        .sectionProviders: "Services",
        .addProvider: "Add Service…",
        .providerCustom: "Custom",
        .configSection: "Configure — %@",
        .nameLabel: "Name",
        .formatLabel: "API format",
        .modelLabel: "Model",
        .modelIdPlaceholder: "model id",
        .customModelTag: "Custom…",
        .customModelLabel: "Custom model",
        .saveButton: "Save",
        .clearButton: "Clear",
        .keySaved: "Saved ✓",
        .keyNotSet: "Not set",
        .testConnection: "Test Connection",
        .testing: "Testing…",
        .testSucceeded: "✓ Connected (%d ms)",
        .sectionShortcut: "Shortcut",
        .shortcutLabel: "Selection-check shortcut",
        .shortcutCaption: "Press with text selected to check it and get suggestions; with no selection, checks the caret's paragraph",
        .recordPrompt: "Press shortcut…",
        .clickToRecord: "Click to record",
        .clearShortcut: "Clear shortcut",
        .needModifier: "Must include ⌃, ⌥ or ⌘",
        .reservedCombo: "Conflicts with a system or common shortcut",
        .recorderA11y: "Selection-check shortcut",
        .hotkeyNotSet: "Not set",

        .sectionLexicon: "Lexicon",
        .addEntry: "Add Entry",
        .lexiconCaption: "Replace and avoid entries produce personal-preference underlines; keep entries hide other hints at the same spot.",
        .lexiconSharedNote: "The lexicon is used by both local checking and AI rewrite.",
        .cancelButton: "Cancel",
        .showInFinder: "Show in Finder",
        .kindLabel: "Kind",
        .termPlaceholder: "Term",
        .replacePlaceholder: "Replacement",
        .matchLabel: "Match",
        .deleteEntryA11y: "Delete entry",
        .lexiconKindReplace: "Replace",
        .lexiconKindAvoid: "Avoid",
        .lexiconKindKeep: "Keep",
        .matchExact: "Exact",
        .matchCaseInsensitive: "Ignore case",
        .matchWholeWord: "Whole word",
        .errEmptyTerm: "Term can't be empty",
        .errTermTooLong: "Term can be at most %d characters",
        .errDuplicate: "Duplicate entry",

        .sectionSkills: "Rewrite Skills",
        .safetyDisclosure: "Safety rules (fixed, read-only)",
        .skillForZh: "For Chinese text",
        .skillForEn: "For English text",
        .skillImport: "Import Skill…",
        .skillBuiltinName: "De-AI (default)",
        .migratedSkillName: "My style (migrated)",
        .skillLangZh: "Chinese",
        .skillLangEn: "English",
        .skillLangAny: "Universal",
        .skillSize: "%d chars · ~%d tokens",
        .skillLongWarning: "Long: each rewrite is slower and costlier",
        .skillViewEdit: "View/Edit",
        .skillDuplicate: "Duplicate as New Skill",
        .builtinReadonlyNote: "Built-in skills are read-only",
        .skillDeleteTitle: "Delete skill “%@”?",
        .skillDeleteMessage: "The skill file will be removed from disk.",
        .skillTooLarge: "Skill body is %d chars; the limit is %d",
        .skillNotMarkdown: "Choose a .md file or a folder containing SKILL.md",
        .skillUnreadable: "Could not read the selected file",
        .skillDeleted: "This skill no longer exists",
        .skillNameLabel: "Name",
        .skillDescLabel: "Description",
        .skillBodyLabel: "Body",
        .skillLanguageLabel: "Language",

        .menuAutoUnderline: "Auto-underline",
        .menuCheckInApp: "Check in %@",
        .menuAppGroups: "App types",
        .menuSettings: "Settings…",
        .menuRuleTest: "Rule Test Window",
        .menuUIPreview: "UI Preview",
        .menuQuit: "Quit DeAI",

        .stepperPrev: "Previous",
        .stepperNext: "Next",
        .stepperA11y: "%d of %d",
        .closeTooltip: "Close",
        .dismissA11y: "Dismiss suggestion",
        .replaceWithA11y: "Replace with: %@",
        .deleteRow: "Delete",
        .deleteTextA11y: "Delete this text",
        .applyLabel: "Apply",
        .rewriteA11y: "AI rewrite",
        .rewriteTooltip: "Rewrite this passage with AI",
        .rewriteSelectionTooltip: "Rewrite the selection with AI",
        .ignoreLabel: "Ignore",
        .editEntry: "Edit Entry…",
        .addKeepEntry: "Keep This Word",
        .rememberFix: "Remember This Fix",
        .disableRule: "Disable This Rule",
        .moreLabel: "More",
        .emptyTag: "Check complete",
        .emptyBody: "No issues found",
        .emptyFlash: "Still no issues found",
        .recheckButton: "Re-check",
        .appliedLabel: "Applied",
        .applyFailedLabel: "Couldn't apply",

        .rewriteTitle: "AI Rewrite",
        .rewriting: "Rewriting…",
        .originalLabel: "Original",
        .rewriteLabel: "Rewrite",
        .replaceButton: "Replace",
        .copyButton: "Copy",
        .retryButton: "Retry",
        .openSettings: "Open Settings",
        .noChange: "Nothing to change",
        .rememberToggle: "Remember edits (%d)",
        .rememberSaved: "Added to lexicon",
        .rememberA11y: "Remember edits",
        .pairDelete: "Delete “%@”",
        .pairReplace: "“%@” → “%@”",
        .addToLexicon: "Add to Lexicon",

        .errorTooLong: "Selection is too long (max %d characters)",
        .errorConfigureAI: "Set up an AI service in Settings first",
        .errorReadText: "Couldn't read the text",
        .errorOriginalChanged: "The original text changed — rewrite again",
        .errorInvalidBaseURL: "Invalid base URL: %@",
        .errorHTTPAuth: "Invalid or unauthorized API key",
        .errorHTTPRate: "Too many requests or quota exhausted",
        .errorParseResponse: "Couldn't parse the response",
        .errorNoText: "The response contains no text",
        .hotkeyTaken: "That shortcut is taken by another app — pick another",
        .hotkeyFailed: "Shortcut registration failed (error %d)",

        .permissionTitle: "Accessibility Permission",
        .permissionBody: "DeAI reads the frontmost app's text to underline grammar, AI-tone and Markdown issues; secure fields like passwords are skipped.",
        .permissionNote: "Enable DeAI in the Accessibility list — this window closes automatically once granted.",
        .openSystemSettings: "Open System Settings",

        .ruleTestTitle: "Rule Test",
        .findingsCount: "%d findings",
        .stripMarkdown: "Strip Markdown",
        .originalPrefix: "Original: %@",
        .suggestionsPrefix: "Suggestions: %@",

        .windowSettings: "DeAI Settings",
        .windowPermission: "DeAI — Accessibility Permission",
        .windowRuleTest: "Debug: Rule Test",

        .turnOff: "Turn off",
        .turnOn: "Turn on",
        .valueOn: "On",
        .valueOff: "Off",

        .personalReplaceMessage: "Personal preference: use “%@” instead of “%@”",
        .personalAvoidMessage: "Personal preference: avoid “%@”",
    ]

    static func t(_ key: Key, _ lang: UILanguage) -> String {
        let table = lang == .en ? en : zh
        return table[key] ?? key.rawValue
    }

    /// Format variant for interpolated strings (`%@`, `%d` placeholders).
    static func f(_ key: Key, _ lang: UILanguage, _ args: CVarArg...) -> String {
        String(format: t(key, lang), arguments: args)
    }
}

private struct DeAIUILanguageKey: EnvironmentKey {
    static let defaultValue: UILanguage = .zh
}

extension EnvironmentValues {
    /// Every DeAI surface reads strings through this. Roots inject it from
    /// their observed source (AppSettings.uiLanguage / model.lang), so a
    /// settings change re-renders everything live.
    var deaiUILanguage: UILanguage {
        get { self[DeAIUILanguageKey.self] }
        set { self[DeAIUILanguageKey.self] = newValue }
    }
}

/// Re-renders its content when `AppSettings.uiLanguage` changes and exposes
/// it through `deaiUILanguage`. For window/panel roots that don't otherwise
/// observe AppSettings — requires `AppSettings` in the environment.
struct LanguageScoped<Content: View>: View {
    @EnvironmentObject private var settings: AppSettings
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.environment(\.deaiUILanguage, settings.uiLanguage)
    }
}

extension L10n {
    /// The suggestion card's finding explanation. The Rust core emits
    /// Chinese messages for our own rules (and dynamically built ones for
    /// personal entries), so English is produced here keyed by ruleId.
    /// Harper messages are already English — `harper.*` passes through,
    /// as does any unknown id.
    static func findingMessage(
        _ finding: Finding, matched: String, lang: UILanguage
    ) -> String {
        guard lang == .en else { return finding.message }
        switch finding.ruleId {
        case "personal.replace":
            return f(.personalReplaceMessage, .en,
                     finding.suggestions.first ?? "", matched)
        case "personal.avoid":
            return f(.personalAvoidMessage, .en, matched)
        default:
            if finding.ruleId.hasPrefix("harper.") { return finding.message }
            return enRuleMessages[finding.ruleId] ?? finding.message
        }
    }

    /// English explanations for every non-Harper rule id the core emits —
    /// verified against `coreRuleIds` by tests (keyed by ruleId, NOT by
    /// inspecting the Chinese message text).
    static let enRuleMessages: [String: String] = [
        "zh.fanan":
            "Misconstrual pattern: sets up a supposed mistake, then corrects it",
        "zh.fanan_loose":
            "Misconstrual pattern: forced “not X, but Y” contrast",
        "zh.prompt_colon":
            "Prompt-style colon introducing content",
        "zh.empty_list_intro":
            "Filler sentence that only introduces the list",
        "zh.ordinal_heading":
            "Numbered headings: consecutive headings start with ordinals",
        "zh.ordinal_heading_plain":
            "Numbered lines: consecutive short lines start with ordinals",
        "zh.banned_opener":
            "Stock opener (e.g. “to put it bluntly”, “conclusion first”)",
        "zh.zero_anaphor":
            "Paragraph-opening comment that doesn't refer back to the text",
        "zh.persona_metaphor":
            "Personification: the tool is compared to an idealized person",
        "zh.dash": "Dash used as a dramatic reveal",
        "zh.dunhao_list":
            "Dense enumeration packed into one clause",
        "zh.nominalization":
            "Nominalization: an action written as “the … of”",
        "zh.dang_shi":
            "Translation tone: leading “when …, ” clause",
        "zh.topic_shell":
            "Translation tone: topicalizing shell phrase",
        "zh.lead_connective":
            "Translation tone: sentence-initial connective as signpost",
        "zh.this_means":
            "Translation tone: “this means”-style restatement",
        "zh.isomorphic":
            "Isomorphic sentences: adjacent sentences share one structure",
        "zh.long_attr":
            "Translation tone: overlong leading attribute",

        "en.chat_leftover": "Chat leftover: conversational boilerplate",
        "en.filler_opener": "Filler opener — safe to delete",
        "en.stock_phrase": "AI stock phrase",
        "en.inflated": "Inflated wording",
        "en.vague_attribution": "Vague attribution",
        "en.not_but": "AI pattern: “not … but”",
        "en.not_only": "AI pattern: “not only … but also”",
        "en.em_dash": "Em dash",
        "en.signpost": "Signpost word at sentence start",
        "en.ai_vocab": "AI vocabulary",

        "md.code_fence": "Markdown residue: fenced code block",
        "md.hr": "Markdown residue: horizontal rule",
        "md.table_row": "Markdown residue: table row",
        "md.heading": "Markdown residue: heading marker",
        "md.blockquote": "Markdown residue: blockquote marker",
        "md.list_bullet": "Markdown residue: list bullet",
        "md.bold": "Markdown residue: bold markers",
        "md.strike": "Markdown residue: strikethrough markers",
        "md.inline_code": "Markdown residue: inline code backticks",
        "md.link": "Markdown residue: link syntax",
        "md.image": "Markdown residue: image syntax",
        "md.italic": "Markdown residue: italic markers",
        "md.escape": "Markdown residue: escape backslash",
    ]

    /// Every non-Harper rule id `deai-core` can emit — mirrors
    /// `core/crates/deai-core/RULES.md` and the rule sources under
    /// `src/rules/` + `src/personal.rs`. The coverage test asserts each id
    /// resolves to an English message (personal.* are built dynamically).
    static let coreRuleIds: [String] = [
        "zh.fanan", "zh.fanan_loose", "zh.prompt_colon", "zh.empty_list_intro",
        "zh.ordinal_heading", "zh.ordinal_heading_plain", "zh.banned_opener",
        "zh.zero_anaphor", "zh.persona_metaphor", "zh.dash", "zh.dunhao_list",
        "zh.nominalization", "zh.dang_shi", "zh.topic_shell",
        "zh.lead_connective", "zh.this_means", "zh.isomorphic", "zh.long_attr",
        "en.chat_leftover", "en.filler_opener", "en.stock_phrase",
        "en.inflated", "en.vague_attribution", "en.not_but", "en.not_only",
        "en.em_dash", "en.signpost", "en.ai_vocab",
        "md.code_fence", "md.hr", "md.table_row", "md.heading",
        "md.blockquote", "md.list_bullet", "md.bold", "md.strike",
        "md.inline_code", "md.link", "md.image", "md.italic", "md.escape",
        "personal.replace", "personal.avoid",
    ]
}
