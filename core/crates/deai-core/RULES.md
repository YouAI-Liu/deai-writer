# DeAI 规则规格 v1

本文件是规则实现的唯一依据。中文规则来自 `lieflat-less-ai-tone`（283 万字语料验证），英文规则取自 blader/humanizer 中可用正则可靠检测的部分，Markdown 规则为确定性清理。

## 通用约定

- 偏移：UTF-16 code unit，`[start, end)`。
- 段落：按 `\n` `\r` `\u2028` `\u2029` 切分（Word 用 LF，TextEdit 用 CR）。
- 句子：段内按 `。！？!?`（及其后紧跟的 `”」』）`）切分。“句首”= 段首，或紧跟在句末标点（含其后引号与空白）之后。
- 置信层级 `tier`：1 = 高置信，2 = 标准，3 = 敏感。`CheckOptions.sensitivity`（1/2/3，默认 2）：只输出 `tier <= sensitivity` 的结果。harper 语法结果 tier = 1。
- 排除区（AI 味规则一律跳过，Markdown 规则除外）：
  - 围栏代码块（``` 行之间，含围栏行）与行内代码（反引号之间）。
  - 中文规则额外跳过引号内文字：`“…”` `「…」` `『…』`，以及成对的 ASCII `"…"`。命中起点落在排除区内即丢弃。
- 去重：
  - 同一类别、区间完全相同：保留 tier 小的；tier 相同保留规则表中靠前的。
  - 其余重叠结果默认全部保留，**只有**以下显式取代对在区间重叠时丢弃右者（左 > 右）：
    `zh.prompt_colon` > `zh.this_means`；`zh.zero_anaphor` > `zh.this_means`；`zh.banned_opener` > `zh.zero_anaphor`；`zh.fanan` > `zh.fanan_loose`；`zh.zero_anaphor` > `zh.lead_connective`；`en.chat_leftover` / `en.filler_opener` / `en.stock_phrase` / `en.inflated` > `en.ai_vocab`；`en.stock_phrase` > `en.inflated`；`en.not_but` > `en.not_only`；`md.hr` > `md.list_bullet`；`md.image` > `md.link`。
  - Markdown 类别除上表外不去重（`**[x](u)**` 这类嵌套标记必须同时报出 bold 与 link）。
  - 不同类别之间不去重。
- `suggestions` 为空表示无确定性修复，UI 提供“AI 改写”。
- `message` 用中文，格式「<短标题>：<一句说明>」。

## 中文 AI 味（category = AiToneZh）

按优先级排列（同时也是去重顺序）。

| id | tier | 触发 | 修复建议 |
|---|---|---|---|
| zh.fanan | 2 | `(?:不是\|并非\|不在于)[^，。！？\n]{1,20}，?(?:而是\|而在于)`；`与其说[^。！？\n]{1,30}不如说`；`看似[^。！？\n]{1,20}实则`；`表面上?[^。！？\n]{1,20}实际上?`；`你以为[^。！？\n]{1,30}其实`。区间 = 整个匹配 | 无 |
| zh.fanan_loose | 3 | `不是[^，。！？\n]{1,20}，是`（且未被 zh.fanan 覆盖） | 无 |
| zh.prompt_colon | 1 | 提示语 + 冒号，正则见下文 P1。跳过：所在行以 `#` 开头；冒号后紧跟 `“` `「` `"`。区间 = 提示语 + 冒号 | 匹配处于句首时给 `""`（删掉提示语），否则无 |
| zh.empty_list_intro | 1 | 非标题行以 `：` 或 `:` 结尾（去尾空白后），且下一非空行是列表项 L1。区间 = 整行（不含换行） | 无 |
| zh.ordinal_heading | 1 | 连续 ≥3 个“标题行”以序号开头：`^[一二三四五六七八九十]+、` 或 `^第[一二三四五六七八九十]+[、，：:\s]`。标题行 = `#` 开头行（序号在 `#+\s*` 之后匹配），或整行只有 `**…**` 加粗（序号在 `**` 之后匹配）。“连续”指中间只隔非标题行也算，序列被一个不带序号的标题打断则重新计数。区间 = 每个序号前缀（含 `、`/标点/空白） | `""` |
| zh.ordinal_heading_plain | 2 | 同上，但标题行 = 独立短行（UTF-16 长度 ≤ 30，不以 `。！？；，` 结尾，且不是列表项），用于 Word 等纯文本 | `""` |
| zh.banned_opener | 1 | `说白了\|说穿了\|先说结论`，含其后可选的 `[，,：:]`。区间 = 短语 + 标点 | `""` |
| zh.zero_anaphor | 1 | 非首段（段落过滤见 Z1），段首匹配 Z2，且段首第一句不含回指词 `这\|那\|其\|此\|上面\|前面\|上述\|以上\|该`。区间 = 段首评论语 | 评论语为 听起来/看起来/看上去/听上去 时给 `"这"+原文`，否则无 |
| zh.persona_metaphor | 1 | `(?:像\|如同\|好比\|相当于\|宛如\|犹如)是?(?:一位\|一个\|一名)([^，。！？\n]{0,12}?)(?:导师\|秘书\|助手\|助理\|顾问\|管家\|审查员\|实习生\|教练\|向导\|守护者\|参谋\|军师)`，且满足其一：匹配内含 `永不\|不知疲倦\|智慧的\|全能的\|贴心的\|贴身的\|忠实的\|耐心的\|无所不知\|秒级响应`；或同句内匹配之后出现 `不仅[^。！？\n]*更`。不带褒义修饰的具体人物喻体（如“像一个老师傅”）不命中。区间 = 匹配 | 无 |
| zh.dash | 2 | `——`（也接受单个 `—` 前后都是汉字的情况）。区间 = 破折号 | `"，"` |
| zh.dunhao_list | 2 | `[^，。！？；：、\n]{1,14}、[^，。！？；：、\n]{1,14}、[^，。！？；：、\n]{1,14}`（一个分句内两个以上顿号）。跳过列表项行（L1）。区间 = 匹配 | 无 |
| zh.nominalization | 2 | `(?:完成\|实现\|进行\|开展)了?对?[^，。\n]{0,10}的(?:优化\|提升\|调整\|分析\|改造\|升级)` | 无 |
| zh.dang_shi | 2 | 句首 `当([^，。\n]{2,20})时，`，且捕获组不以 `的` 结尾（排除“的时候”）。区间 = 从 `当` 到 `，` | `捕获组 + "，"` |
| zh.topic_shell | 2 | 句首 `对于[^，。\n]{2,15}来说\|对[^，。\n]{2,15}而言\|就[^，。\n]{2,15}而言\|关于[^，。\n]{2,15}，\|在[^，。\n]{2,12}方面` | 无 |
| zh.lead_connective | 2 / 3 | `(?:然而\|因此\|此外\|与此同时\|换言之\|总而言之)[，、,]`：在段首为 tier 2，在段中句首为 tier 3 | 无 |
| zh.this_means | 2 | 句首 `(?:这意味着\|这表明\|这说明\|换句话说)[，,]?`（`换句话说：` 已由 zh.prompt_colon 覆盖，按去重保留后者） | 无 |
| zh.isomorphic | 2 / 3 | 段内句子（UTF-16 长度 > 10）的结构指纹 = (`，` 个数, 是否含 `：`, 是否含 `（` 或 `(`, 字数 / 15)。逗号数 ≥ 1 且连续 3 句指纹相同为 tier 2，连续 2 句为 tier 3。区间 = 这几句合起来的范围；同一段内取最长的连续段，不重复报告 | 无 |
| zh.long_attr | 3 | `(?:一个\|一种\|一套\|这种\|这个)[^，。、；：！？\n]{15,}的[一-鿿]{2,5}`；`的[^，。]{1,8}的[^，。]{1,8}的` | 无 |

**P1（提示性冒号）**：
```
(?:一句话(?:总结|说|概括)|简单说|说白了|总结|小结|结论|核心(?:是|在于|观点)?|关键(?:是|在于)?|重点(?:是)?|原因(?:如下|有|在于)?|问题(?:是|在于)?|答案(?:是)?|本质(?:是|上)?|定义(?:是)?|具体(?:来说|如下|包括)?|举例(?:来说)?|换句话说|也就是说|我的(?:观点|判断|结论)|建议(?:是)?)[：:]
```

**L1（列表项行）**：`^\s*(?:[-*+•·]\s|\d+[.、)）]\s?|[（(]?[一二三四五六七八九十]+[、)）])`

**Z1（参与零回指判断的段落）**：去首尾空白后长度 ≥ 8，且不以 `#` `|` ``` ` ``` `>` `- ` `* ` `!` `[` 开头。“首段”= 第一个通过过滤的段落。

**Z2（段首评论语）**：
```
^(?:听起来|看起来|看上去|听上去|说白了|说到底|换句话说|意味着|值得注意|不难看出|细看|再看|回过头看|问题在于|原因在于|结果是|有意思的是|更重要的是|关键在于|真正的)
```

**明确不做的（lieflat「不作为改写理由」）**：句长或段长不够参差、虚词偏少、少用代词、被动句、名词化或长句本身、正文里的“首先……其次”、句内同构排比、问句、比喻本身。不得为这些添加规则。

## 英文 AI 味（category = AiToneEn）

匹配一律不区分大小写，按词边界匹配。

| id | tier | 触发 | 修复建议 |
|---|---|---|---|
| en.chat_leftover | 1 | `I hope this helps[.!]?`、`Certainly!`、`Of course!`、`Great question[.!]?`、`As an AI(?: language model)?`、`as of my last (?:knowledge )?update`、`let me know if you have any (?:other\|further )?questions[.!]?`、`I'?d be happy to help[.!]?`、`feel free to (?:reach out\|ask)[^.!?\n]*[.!]?` | `""` |
| en.filler_opener | 1 | 句首 `(?:it'?s\|it is) (?:worth noting\|important to note\|worth mentioning) that\s+`、`needless to say,\s*`、`it goes without saying that\s+`。区间包含其后第一个字母 | 该字母转大写（即删掉套话并把句首字母大写） |
| en.stock_phrase | 1 | `delves? into`、`in today'?s (?:fast-paced\|digital\|modern) (?:world\|age\|landscape)`、`in the ever-evolving (?:world\|landscape\|realm) of`、`navigat(?:e\|ing) the complexities of`、`(?:serves\|stands) as a testament to`、`a testament to`、`plays? a (?:crucial\|pivotal\|vital\|key) role`、`rich tapestry`、`tapestry of`、`unlock(?:s\|ing)? the (?:full )?potential`、`unleash(?:es\|ing)? the power`、`embark(?:s\|ing)? on a journey`、`game[- ]changer` | 无 |
| en.inflated | 2 | `mark(?:s\|ed\|ing)? a (?:pivotal\|significant\|major\|new) (?:moment\|milestone\|turning point\|shift\|era)`、`(?:underscor\|highlight)(?:es\|ed\|ing\|s)? (?:the\|its\|their) (?:importance\|significance)`、`setting the stage for`、`paving the way for`、`in the realm of`、`ever-evolving`、`evolving landscape`、`indelible mark`、`deeply rooted` | 无 |
| en.vague_attribution | 2 | `(?:experts\|studies\|research\|observers\|critics\|scientists\|many) (?:say\|believe\|suggest\|argue\|agree\|have shown\|show)` | 无 |
| en.not_but | 2 | `\b(?:it'?s\|this is\|that'?s\|it is) not (?:just \|only \|merely )?(?:about )?[^.!?\n]{1,40}?[,;—–]\s*(?:it'?s\|but)\b` | 无 |
| en.not_only | 3 | `not only [^.!?\n]{1,40}? but (?:also )?` | 无 |
| en.em_dash | 2 | `—`（U+2014），但不得与另一个 `—` 相邻，且两侧最近的非空格字符都不是 CJK（U+3000–U+303F、U+4E00–U+9FFF、U+FF00–U+FFEF）；以及前后带空格的 ` -- `。区间包含两侧空格 | `", "` |
| en.signpost | 2 / 3 | 句首 `(?:Moreover\|Furthermore\|Additionally\|In addition\|Notably\|Importantly\|Ultimately\|Consequently\|In conclusion\|In summary\|Overall),`：同一段出现 ≥ 2 次时每处为 tier 2，否则为 tier 3 | 无 |
| en.ai_vocab | 2 / 3 | 整词：`delve`、`tapestry`、`testament`、`pivotal`、`intricate`、`multifaceted`、`underscore(s\|d)?`、`showcas(e\|es\|ed\|ing)`、`bolster(s\|ed\|ing)?`、`garner(s\|ed\|ing)?`、`realm`、`seamless(ly)?`、`leverag(e\|es\|ed\|ing)`、`foster(s\|ed\|ing)?`、`vibrant`、`meticulous(ly)?`、`paramount`、`nuanced`、`holistic`、`synergy`、`elevat(e\|es\|ed\|ing)`、`commendable`、`noteworthy`、`embark(s\|ed\|ing)?`。同一段内不同词 ≥ 3 个时每处为 tier 2，否则为 tier 3。已被其他 en.* 结果覆盖的区间按去重规则处理 | 无 |

## Markdown 残留（category = Markdown）

不受排除区限制，但围栏代码块内部只检查围栏行本身。

| id | tier | 触发 | 修复建议 |
|---|---|---|---|
| md.bold | 1 | `\*\*([^*\n]+?)\*\*`、`__([^_\n]+?)__` | `$1` |
| md.strike | 1 | `~~([^~\n]+?)~~` | `$1` |
| md.heading | 1 | 行首 `#{1,6}[ \t]+`。区间 = 井号和空白 | `""` |
| md.blockquote | 1 | 行首 `>[ \t]?` | `""` |
| md.inline_code | 1 | `` `([^`\n]+)` `` | `$1` |
| md.code_fence | 1 | 整行匹配 `^\s*```[\w+-]*\s*$`。区间 = 该行加其后的换行（若有） | `""` |
| md.hr | 1 | 整行匹配 `^\s*(?:-{3,}\|\*{3,}\|_{3,})\s*$` | `""` |
| md.link | 1 | `\[([^\]\n]+)\]\(([^)\s]+)\)`，且前一个字符不是 `!` | `$1`、`$1 ($2)`、`$2` |
| md.image | 1 | `!\[([^\]\n]*)\]\([^)\n]+\)` | `$1`（为空则 `""`） |
| md.list_bullet | 2 | 行首 `[ \t]*[-*+][ \t]+`（不能是 md.hr） | `""` |
| md.italic | 2 | `*X*`：前一个字符不是 `*`、字母或数字，后一个字符不是 `*`、字母或数字，X 不以空白开头或结尾，也不含 `*` 和换行（Rust regex 不支持 lookaround，需手动判断） | `X` |
| md.table_row | 2 | 整行匹配 `^\s*\|.*\|\s*$` | 无 |
| md.escape | 2 | `\\([*_#`>\[\]~])` | `$1` |

## 公共 API 增量

- `Finding` 新增 `tier: u8`。
- `CheckOptions` 新增 `sensitivity: u8`（默认 2，取值限制在 1..=3）。
- 新增 `strip_markdown(text: &str, opts: &CheckOptions) -> String`：取所有 Markdown 结果（不受 sensitivity 过滤，tier 1 和 tier 2 全取），从中选出互不重叠的结果、从后往前应用 `suggestions[0]`；没有建议的结果（md.table_row）跳过。应用后重新检查并重复，直到没有可应用的 Markdown 结果或达到 4 轮（覆盖 `**[x](u)**`、`> ## h` 这类嵌套）。用于“整篇清除 Markdown”。
- 新增 `apply_suggestion(text: &str, start: u32, end: u32, replacement: &str) -> String`：工具函数，三端共用。

## 性能要求

- 正则全部在首次使用时编译一次（`std::sync::LazyLock`）。
- 每次 check 先建一张 byte→UTF-16 前缀表，之后的偏移换算都是 O(1)；harper 的 char 下标同理建 char→UTF-16 表。
- 指标（release，Apple Silicon）：20,000 UTF-16 单位的中英混排文本，非语法规则全部跑完 < 10 ms；含 harper 时一并报告实测耗时。
