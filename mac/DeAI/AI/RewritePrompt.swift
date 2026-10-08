import Foundation
import OSLog

/// A local finding passed to the model as a hint.
struct RewriteHint: Equatable {
    let ruleId: String
    let matched: String
    let message: String
}

/// Prompt text for the AI rewrite. The constraints mirror the
/// lieflat-less-ai-tone whitelist approach: only fix AI tells, never touch
/// facts, keep structure. Edit with care — this text defines what the model
/// is allowed to change.
enum RewritePrompt {
    private static let log = Logger(
        subsystem: "com.local.deai", category: "rewrite"
    )

    /// Fixed safety rules (former rules 1, 2, 3, 5, 7 + output format) —
    /// not user-editable; the user's style text is appended after it.
    static let safetyBlock = """
    你是一名中英文文字编辑，只做一件事：去掉文字里的"AI 腔"，让它读起来像作者本人写的。

    硬性规则：
    1. 不增加、不删除任何事实、数字、日期、人名、机构名、引文、链接、出处和限定语（如"可能""约""部分""一些"）。
    2. 保持原文语言：中文仍为中文，英文仍为英文，中英混排保持原样。
    3. 保持原文的段落数量和顺序，不合并、不拆分段落；不添加标题、列表、加粗等 Markdown 格式。原文中残留的 Markdown 符号（**、#、行首的 - 或 * 列表符、`、> 等）要去掉，保留其中的文字。
    4. 篇幅与原文相近，通常不超过原文的 110%。
    5. 如果原文没有需要修改的地方，原样输出原文。

    输出格式：只输出改写后的正文。不要解释，不要加引号或代码块，不要写"改写如下"之类的话。
    """

    /// Default `style.md` content (former rules 4 and 6): what "AI 腔" is
    /// and that only AI-tone spots may change. The user edits this freely.
    static let defaultStyle = """
    只修改有 AI 腔的地方；本来自然的句子原样保留，不要为了"改了"而改，也不要换成你偏好的说法。
    需要去掉的 AI 腔包括（不限于）：空洞的开场白和总结句（"总的来说""值得注意的是""说白了""In conclusion""It's worth noting"）；套话和夸大词（"赋能""至关重要""深度融合""delve""pivotal""tapestry""seamless"）；"不是……而是……""not X but Y"式的刻意对比；凑数的三项排比；破折号堆叠；"这意味着""这不仅……更……"之类的空转承接；翻译腔（多余的"的""被""进行""对……进行……"）；对话残留（"希望对你有帮助""当然！""Great question""I hope this helps"）。
    """

    /// System prompt = fixed safety block + the user's style text
    /// (`style.md`, capped at 4000 chars).
    static func system(style: String) -> String {
        var s = style
        if s.count > PersonalLexiconStore.maxStyleLength {
            s = String(s.prefix(PersonalLexiconStore.maxStyleLength))
            log.notice("style.md truncated to \(PersonalLexiconStore.maxStyleLength) chars")
        }
        return safetyBlock + "\n\n写作风格与偏好（用户自定义）：\n" + s
    }

    /// The lexicon block prepended to the user message when non-empty.
    static func lexiconSection(_ entries: [LexiconEntry]) -> String {
        let capped = entries.filter(\.isValid)
            .prefix(PersonalLexiconStore.maxEntries)
        let keep = capped.filter { $0.kind == .keep }.map(\.term)
        let replace = capped.filter { $0.kind == .replace }
        let avoid = capped.filter { $0.kind == .avoid }.map(\.term)
        guard !keep.isEmpty || !replace.isEmpty || !avoid.isEmpty else {
            return ""
        }
        var out = "个人词库（必须遵守）：\n"
        if !keep.isEmpty {
            out += "必须保留原样的词：" + keep.map { "「\($0)」" }.joined() + "\n"
        }
        if !replace.isEmpty {
            out += "必须这样替换："
                + replace.map {
                    "「\($0.term)」→「\($0.replacement ?? "")」"
                }.joined(separator: "，") + "\n"
        }
        if !avoid.isEmpty {
            out += "避免使用：" + avoid.map { "「\($0)」" }.joined() + "\n"
        }
        return out + "\n"
    }

    static func user(
        text: String,
        hints: [RewriteHint],
        lexicon: [LexiconEntry] = []
    ) -> String {
        var out = lexiconSection(lexicon)
        if !hints.isEmpty {
            out += "本地规则检测到的问题（仅供参考：不必逐条照改，也不要只改这些）：\n"
            for h in hints {
                out += "- [\(h.ruleId)] \"\(h.matched)\"：\(h.message)\n"
            }
            out += "\n"
        }
        out += "原文：\n<<<\n\(text)\n>>>"
        return out
    }

    /// Probe used by the settings "测试连接" button.
    static let pingSystem = "Reply with exactly: OK"
    static let pingUser = "ping"
}
