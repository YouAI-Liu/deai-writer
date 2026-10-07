//! 中文 AI 味规则，按 RULES.md 表格顺序排列（顺序同时用于同类去重）。

use std::sync::LazyLock;

use regex::Regex;

use super::{Ctx, Rule};
use crate::text::{is_heading_line, is_list_item};
use crate::{Category, Finding};

const CAT: Category = Category::AiToneZh;

fn mk(ctx: &Ctx, id: &'static str, msg: &'static str, m: regex::Match<'_>, tier: u8) -> Finding {
    ctx.make(CAT, id, msg, m.start()..m.end(), tier, vec![])
}

/// Regex-driven zh rules share this shape: skip matches starting in an
/// exclusion zone (code or quotes).
fn regex_findings(
    ctx: &Ctx,
    re: &Regex,
    id: &'static str,
    msg: &'static str,
    tier: u8,
) -> Vec<Finding> {
    re.find_iter(ctx.text)
        .filter(|m| !ctx.exclusions.zh_excluded(m.start()))
        .map(|m| mk(ctx, id, msg, m, tier))
        .collect()
}

// ---------- zh.fanan (tier 2) ----------

pub struct Fanan;

static FANAN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?:不是|并非|不在于)[^，。！？\n]{1,20}，?(?:而是|而在于)|与其说[^。！？\n]{1,30}不如说|看似[^。！？\n]{1,20}实则|表面上?[^。！？\n]{1,20}实际上?|你以为[^。！？\n]{1,30}其实",
    )
    .unwrap()
});

impl Rule for Fanan {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        regex_findings(
            ctx,
            &FANAN,
            "zh.fanan",
            "翻案腔：先立一个误解再推翻的句式",
            2,
        )
    }
}

// ---------- zh.fanan_loose (tier 3) ----------

pub struct FananLoose;

static FANAN_LOOSE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"不是[^，。！？\n]{1,20}，是").unwrap());

impl Rule for FananLoose {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        // overlaps with zh.fanan are removed by dedupe (fanan is tier 2)
        regex_findings(
            ctx,
            &FANAN_LOOSE,
            "zh.fanan_loose",
            "翻案腔：「不是…，是…」对比",
            3,
        )
    }
}

// ---------- zh.prompt_colon (tier 1) ----------

pub struct PromptColon;

/// P1 in RULES.md.
static PROMPT_COLON: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?:一句话(?:总结|说|概括)|简单说|说白了|总结|小结|结论|核心(?:是|在于|观点)?|关键(?:是|在于)?|重点(?:是)?|原因(?:如下|有|在于)?|问题(?:是|在于)?|答案(?:是)?|本质(?:是|上)?|定义(?:是)?|具体(?:来说|如下|包括)?|举例(?:来说)?|换句话说|也就是说|我的(?:观点|判断|结论)|建议(?:是)?)[：:]",
    )
    .unwrap()
});

impl Rule for PromptColon {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        PROMPT_COLON
            .find_iter(ctx.text)
            .filter(|m| {
                if ctx.exclusions.zh_excluded(m.start()) {
                    return false;
                }
                let line = match ctx.line_at(m.start()) {
                    Some(l) => l,
                    None => return false,
                };
                if is_heading_line(ctx.line_text(line)) {
                    return false;
                }
                // skip if the char right after the colon opens a quote
                !matches!(ctx.text[m.end()..].chars().next(), Some('“' | '「' | '"'))
            })
            .map(|m| {
                // at sentence start the prompt phrase can be deleted outright
                let suggestions = if ctx.is_sentence_start(m.start()) {
                    vec![String::new()]
                } else {
                    vec![]
                };
                ctx.make(
                    CAT,
                    "zh.prompt_colon",
                    "提示语冒号：用提示语引出内容",
                    m.start()..m.end(),
                    1,
                    suggestions,
                )
            })
            .collect()
    }
}

// ---------- zh.empty_list_intro (tier 1) ----------

pub struct EmptyListIntro;

impl Rule for EmptyListIntro {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        let mut out = Vec::new();
        for (i, line) in ctx.lines.iter().enumerate() {
            let lt = ctx.line_text(line);
            if is_heading_line(lt) {
                continue;
            }
            if !matches!(lt.trim_end().chars().last(), Some('：' | ':')) {
                continue;
            }
            // next non-empty line must be a list item
            let next = ctx.lines[i + 1..]
                .iter()
                .find(|l| !ctx.line_text(l).trim().is_empty());
            if let Some(l) = next {
                if is_list_item(ctx.line_text(l)) && !ctx.exclusions.zh_excluded(line.range.start) {
                    out.push(ctx.make(
                        CAT,
                        "zh.empty_list_intro",
                        "空转句：整句只为引出列表",
                        line.range.clone(),
                        1,
                        vec![],
                    ));
                }
            }
        }
        out
    }
}

// ---------- zh.ordinal_heading / zh.ordinal_heading_plain ----------

/// `一、` / `第一、` style ordinal prefix; returns the byte length of the
/// prefix (ordinal + trailing separator char) if present.
static ORDINAL: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(?:[一二三四五六七八九十]+、|第[一二三四五六七八九十]+[、，：:\s])").unwrap()
});

fn ordinal_prefix_len(text: &str) -> Option<usize> {
    ORDINAL.find(text).map(|m| m.end())
}

/// Shared runner: `heading` reports the byte offset inside the trimmed line
/// where the ordinal may start, for lines that count as headings.
fn ordinal_runs(
    ctx: &Ctx,
    id: &'static str,
    msg: &'static str,
    tier: u8,
    heading: impl Fn(&str) -> Option<usize>,
) -> Vec<Finding> {
    let mut out = Vec::new();
    let mut run: Vec<(usize, usize)> = Vec::new(); // byte ranges of ordinal prefixes
    let flush = |run: &mut Vec<(usize, usize)>, out: &mut Vec<Finding>| {
        if run.len() >= 3 {
            for &(s, e) in run.iter() {
                if !ctx.exclusions.zh_excluded(s) {
                    out.push(ctx.make(CAT, id, msg, s..e, tier, vec![String::new()]));
                }
            }
        }
        run.clear();
    };
    for line in ctx.lines {
        let lt = ctx.line_text(line);
        if lt.trim().is_empty() {
            continue; // blank lines neither count nor break a run
        }
        let trimmed = lt.trim_start();
        let trim_off = line.range.start + (lt.len() - trimmed.len());
        // non-heading lines don't affect the run
        if let Some(off) = heading(trimmed) {
            let rest = &trimmed[off..];
            match ordinal_prefix_len(rest) {
                Some(prefix) => run.push((trim_off + off, trim_off + off + prefix)),
                None => flush(&mut run, &mut out), // heading without ordinal resets
            }
        }
    }
    flush(&mut run, &mut out);
    out
}

/// Markdown-ish headings: `#` lines (ordinal after `#+\s*`) or whole-line
/// `**bold**` lines (ordinal after `**`).
static HASH_PREFIX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^#+\s*").unwrap());

pub struct OrdinalHeading;

impl Rule for OrdinalHeading {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        ordinal_runs(
            ctx,
            "zh.ordinal_heading",
            "序号标题：连续小标题用序号开头",
            1,
            |trimmed| {
                if let Some(m) = HASH_PREFIX.find(trimmed) {
                    return Some(m.end());
                }
                if trimmed.starts_with("**") && trimmed.ends_with("**") && trimmed.len() > 4 {
                    return Some(2);
                }
                None
            },
        )
    }
}

/// Plain-text headings: standalone short lines (Word etc.).
pub struct OrdinalHeadingPlain;

impl Rule for OrdinalHeadingPlain {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        ordinal_runs(
            ctx,
            "zh.ordinal_heading_plain",
            "序号标题：连续短行用序号开头",
            2,
            |trimmed| {
                let t = trimmed.trim_end();
                let utf16_len: u32 = t.chars().map(|c| c.len_utf16() as u32).sum();
                if t.is_empty() || utf16_len > 30 {
                    return None;
                }
                if matches!(t.chars().last(), Some('。' | '！' | '？' | '；' | '，')) {
                    return None;
                }
                if is_list_item(t) {
                    return None;
                }
                Some(0)
            },
        )
    }
}

// ---------- zh.banned_opener (tier 1) ----------

pub struct BannedOpener;

static BANNED_OPENER: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?:说白了|说穿了|先说结论)[，,：:]?").unwrap());

impl Rule for BannedOpener {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        BANNED_OPENER
            .find_iter(ctx.text)
            .filter(|m| !ctx.exclusions.zh_excluded(m.start()))
            .map(|m| {
                ctx.make(
                    CAT,
                    "zh.banned_opener",
                    "禁用起手式：「说白了／说穿了／先说结论」",
                    m.start()..m.end(),
                    1,
                    vec![String::new()],
                )
            })
            .collect()
    }
}

// ---------- zh.zero_anaphor (tier 1) ----------

pub struct ZeroAnaphor;

/// Z2: paragraph-initial review phrases (anchored at the paragraph start
/// exactly — spec `^` does not allow leading whitespace).
static Z2: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^((?:听起来|看起来|看上去|听上去|说白了|说到底|换句话说|意味着|值得注意|不难看出|细看|再看|回过头看|问题在于|原因在于|结果是|有意思的是|更重要的是|关键在于|真正的))",
    )
    .unwrap()
});

static ANAPHOR: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"这|那|其|此|上面|前面|上述|以上|该").unwrap());

/// Z1: paragraph filter — trimmed length ≥ 8 (UTF-16), not starting with a
/// markup/quote char.
fn z1_pass(text: &str) -> bool {
    let t = text.trim();
    let utf16_len: u32 = t.chars().map(|c| c.len_utf16() as u32).sum();
    if utf16_len < 8 {
        return false;
    }
    !matches!(t.chars().next(), Some('#' | '|' | '`' | '>' | '!' | '['))
        && !t.starts_with("- ")
        && !t.starts_with("* ")
}

impl Rule for ZeroAnaphor {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        let mut out = Vec::new();
        let mut seen_first = false;
        for line in ctx.lines {
            let lt = ctx.line_text(line);
            if !z1_pass(lt) {
                continue;
            }
            if !seen_first {
                seen_first = true; // the first qualifying paragraph is exempt
                continue;
            }
            let cap = match Z2.captures(lt) {
                Some(c) => c,
                None => continue,
            };
            let g = cap.get(1).unwrap();
            let start = line.range.start + g.start();
            if ctx.exclusions.zh_excluded(start) {
                continue;
            }
            // the first sentence must lack anaphoric references
            let first_sent = match line.sentences.first() {
                Some(s) => &ctx.text[s.clone()],
                None => continue,
            };
            if ANAPHOR.is_match(first_sent) {
                continue;
            }
            let range = start..line.range.start + g.end();
            let matched = g.as_str();
            let suggestions = if matched.starts_with("听") || matched.starts_with("看") {
                vec![format!("这{}", matched)]
            } else {
                vec![]
            };
            out.push(ctx.make(
                CAT,
                "zh.zero_anaphor",
                "零回指：段首评论语没有回指上文的成分",
                range,
                1,
                suggestions,
            ));
        }
        out
    }
}

// ---------- zh.persona_metaphor (tier 1) ----------

pub struct PersonaMetaphor;

static PERSONA: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?:像|如同|好比|相当于|宛如|犹如)是?(?:一位|一个|一名)([^，。！？\n]{0,12}?)(?:导师|秘书|助手|助理|顾问|管家|审查员|实习生|教练|向导|守护者|参谋|军师)",
    )
    .unwrap()
});

static PRAISE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"永不|不知疲倦|智慧的|全能的|贴心的|贴身的|忠实的|耐心的|无所不知|秒级响应")
        .unwrap()
});

static NOT_ONLY_MORE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"不仅[^。！？\n]*更").unwrap());

impl Rule for PersonaMetaphor {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        PERSONA
            .find_iter(ctx.text)
            .filter(|m| {
                if ctx.exclusions.zh_excluded(m.start()) {
                    return false;
                }
                if PRAISE.is_match(m.as_str()) {
                    return true;
                }
                // or: 不仅…更… after the match, inside the same sentence
                let after = ctx
                    .line_at(m.start())
                    .and_then(|l| {
                        l.sentences
                            .iter()
                            .find(|s| s.start <= m.start() && m.start() < s.end)
                    })
                    .map(|s| &ctx.text[m.end()..s.end])
                    .unwrap_or("");
                NOT_ONLY_MORE.is_match(after)
            })
            .map(|m| {
                mk(
                    ctx,
                    "zh.persona_metaphor",
                    "拟人喻体：把工具比作理想化的人",
                    m,
                    1,
                )
            })
            .collect()
    }
}

// ---------- zh.dash (tier 2) ----------

pub struct Dash;

static DASH: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"——|[一-鿿](—)[一-鿿]").unwrap());

impl Rule for Dash {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        DASH.captures_iter(ctx.text)
            .filter_map(|cap| {
                // range = the dash itself, excluding flanking hanzi
                let range = match cap.get(1) {
                    Some(g) => g.start()..g.end(),
                    None => {
                        let m = cap.get(0).unwrap();
                        m.start()..m.end()
                    }
                };
                if ctx.exclusions.zh_excluded(range.start) {
                    return None;
                }
                Some(ctx.make(
                    CAT,
                    "zh.dash",
                    "破折号：揭晓式停顿",
                    range,
                    2,
                    vec!["，".to_string()],
                ))
            })
            .collect()
    }
}

// ---------- zh.dunhao_list (tier 2) ----------

pub struct DunhaoList;

static DUNHAO: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"[^，。！？；：、\n]{1,14}、[^，。！？；：、\n]{1,14}、[^，。！？；：、\n]{1,14}")
        .unwrap()
});

impl Rule for DunhaoList {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        DUNHAO
            .find_iter(ctx.text)
            .filter(|m| {
                if ctx.exclusions.zh_excluded(m.start()) {
                    return false;
                }
                // skip list-item lines
                match ctx.line_at(m.start()) {
                    Some(l) => !is_list_item(ctx.line_text(l)),
                    None => true,
                }
            })
            .map(|m| mk(ctx, "zh.dunhao_list", "顿号罗列：一个分句内密集并列", m, 2))
            .collect()
    }
}

// ---------- zh.nominalization (tier 2) ----------

pub struct Nominalization;

static NOMINAL: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?:完成|实现|进行|开展)了?对?[^，。\n]{0,10}的(?:优化|提升|调整|分析|改造|升级)")
        .unwrap()
});

impl Rule for Nominalization {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        regex_findings(
            ctx,
            &NOMINAL,
            "zh.nominalization",
            "名词化：动作被写成了「…的优化／提升」",
            2,
        )
    }
}

// ---------- zh.dang_shi (tier 2) ----------

pub struct DangShi;

static DANG_SHI: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"当([^，。\n]{2,20})时，").unwrap());

impl Rule for DangShi {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        DANG_SHI
            .captures_iter(ctx.text)
            .filter_map(|cap| {
                let m = cap.get(0).unwrap();
                let g = cap.get(1).unwrap();
                if !ctx.is_sentence_start(m.start()) || ctx.exclusions.zh_excluded(m.start()) {
                    return None;
                }
                if g.as_str().ends_with('的') {
                    return None; // “的时候” is normal colloquial usage
                }
                Some(ctx.make(
                    CAT,
                    "zh.dang_shi",
                    "翻译腔：「当…时，」前置从句",
                    m.start()..m.end(),
                    2,
                    vec![format!("{}，", g.as_str())],
                ))
            })
            .collect()
    }
}

// ---------- zh.topic_shell (tier 2) ----------

pub struct TopicShell;

static TOPIC_SHELL: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"对于[^，。\n]{2,15}来说|对[^，。\n]{2,15}而言|就[^，。\n]{2,15}而言|关于[^，。\n]{2,15}，|在[^，。\n]{2,12}方面",
    )
    .unwrap()
});

impl Rule for TopicShell {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        TOPIC_SHELL
            .find_iter(ctx.text)
            .filter(|m| ctx.is_sentence_start(m.start()) && !ctx.exclusions.zh_excluded(m.start()))
            .map(|m| mk(ctx, "zh.topic_shell", "翻译腔：前置话题壳", m, 2))
            .collect()
    }
}

// ---------- zh.lead_connective (tier 2 at para start / 3 at sentence start) ----------

pub struct LeadConnective;

static LEAD_CONNECTIVE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?:然而|因此|此外|与此同时|换言之|总而言之)[，、,]").unwrap());

impl Rule for LeadConnective {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        LEAD_CONNECTIVE
            .find_iter(ctx.text)
            .filter_map(|m| {
                if ctx.exclusions.zh_excluded(m.start()) {
                    return None;
                }
                let tier = if ctx.is_para_start(m.start()) {
                    2
                } else if ctx.is_sentence_start(m.start()) {
                    3
                } else {
                    return None;
                };
                Some(mk(
                    ctx,
                    "zh.lead_connective",
                    "翻译腔：句首连接词当路标",
                    m,
                    tier,
                ))
            })
            .collect()
    }
}

// ---------- zh.this_means (tier 2) ----------

pub struct ThisMeans;

static THIS_MEANS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?:这意味着|这表明|这说明|换句话说)[，,]?").unwrap());

impl Rule for ThisMeans {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        THIS_MEANS
            .find_iter(ctx.text)
            .filter(|m| ctx.is_sentence_start(m.start()) && !ctx.exclusions.zh_excluded(m.start()))
            .map(|m| mk(ctx, "zh.this_means", "翻译腔：「这意味着」式复述句", m, 2))
            .collect()
    }
}

// ---------- zh.isomorphic (tier 2 for ≥3, tier 3 for 2) ----------

pub struct Isomorphic;

/// Fingerprint = (`，` count, has `：`, has `（`/`(`, utf16 len / 15).
/// Sentences with no `，` never qualify (per RULES.md).
fn fingerprint(s: &str) -> Option<(usize, bool, bool, u32)> {
    let utf16_len: u32 = s.chars().map(|c| c.len_utf16() as u32).sum();
    if utf16_len <= 10 {
        return None;
    }
    let commas = s.matches('，').count();
    if commas == 0 {
        return None;
    }
    Some((
        commas,
        s.contains('：'),
        s.contains('（') || s.contains('('),
        utf16_len / 15,
    ))
}

impl Rule for Isomorphic {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        let mut out = Vec::new();
        for line in ctx.lines {
            // longest run of consecutive sentences sharing a fingerprint
            let mut best: Option<(usize, usize, usize)> = None; // (start_sent, len, _)
            let mut i = 0;
            while i < line.sentences.len() {
                let fp = fingerprint(&ctx.text[line.sentences[i].clone()]);
                match fp {
                    None => i += 1,
                    Some(fp) => {
                        let mut j = i + 1;
                        while j < line.sentences.len()
                            && fingerprint(&ctx.text[line.sentences[j].clone()]) == Some(fp)
                        {
                            j += 1;
                        }
                        let len = j - i;
                        if len >= 2 && best.map(|b| len > b.1).unwrap_or(true) {
                            best = Some((i, len, j));
                        }
                        i = j;
                    }
                }
            }
            if let Some((first, len, last)) = best {
                let tier = if len >= 3 { 2 } else { 3 };
                let range = line.sentences[first].start..line.sentences[last - 1].end;
                if !ctx.exclusions.zh_excluded(range.start) {
                    out.push(ctx.make(
                        CAT,
                        "zh.isomorphic",
                        "同构句式：相邻句子结构雷同",
                        range,
                        tier,
                        vec![],
                    ));
                }
            }
        }
        out
    }
}

// ---------- zh.long_attr (tier 3) ----------

pub struct LongAttr;

static LONG_ATTR: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?:一个|一种|一套|这种|这个)[^，。、；：！？\n]{15,}的[一-鿿]{2,5}|的[^，。]{1,8}的[^，。]{1,8}的",
    )
    .unwrap()
});

impl Rule for LongAttr {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        regex_findings(ctx, &LONG_ATTR, "zh.long_attr", "翻译腔：过长前置定语", 3)
    }
}

pub fn rules() -> Vec<Box<dyn Rule>> {
    vec![
        Box::new(Fanan),
        Box::new(FananLoose),
        Box::new(PromptColon),
        Box::new(EmptyListIntro),
        Box::new(OrdinalHeading),
        Box::new(OrdinalHeadingPlain),
        Box::new(BannedOpener),
        Box::new(ZeroAnaphor),
        Box::new(PersonaMetaphor),
        Box::new(Dash),
        Box::new(DunhaoList),
        Box::new(Nominalization),
        Box::new(DangShi),
        Box::new(TopicShell),
        Box::new(LeadConnective),
        Box::new(ThisMeans),
        Box::new(Isomorphic),
        Box::new(LongAttr),
    ]
}
