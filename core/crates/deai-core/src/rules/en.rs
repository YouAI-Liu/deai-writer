//! English AI-tone rules per RULES.md. All matching is case-insensitive on
//! word boundaries. Exclusion zones: fenced code + inline code (no quotes —
//! quotes are zh-only).

use std::collections::HashSet;
use std::sync::LazyLock;

use regex::Regex;

use super::{Ctx, Rule};
use crate::{Category, Finding};

const CAT: Category = Category::AiToneEn;

fn regex_findings(
    ctx: &Ctx,
    re: &Regex,
    id: &'static str,
    msg: &'static str,
    tier: u8,
    suggestions: Vec<String>,
) -> Vec<Finding> {
    re.find_iter(ctx.text)
        .filter(|m| !ctx.exclusions.code_excluded(m.start()))
        .map(|m| ctx.make(CAT, id, msg, m.start()..m.end(), tier, suggestions.clone()))
        .collect()
}

// ---------- en.chat_leftover (tier 1) ----------

pub struct ChatLeftover;

static CHAT_LEFTOVER: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)\b(?:I hope this helps[.!]?|Certainly!|Of course!|Great question[.!]?|As an AI(?: language model)?|as of my last (?:knowledge )?update|let me know if you have any (?:other|further )?questions[.!]?|I'?d be happy to help[.!]?|feel free to (?:reach out|ask)[^.!?\n]*[.!]?)",
    )
    .unwrap()
});

impl Rule for ChatLeftover {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        regex_findings(
            ctx,
            &CHAT_LEFTOVER,
            "en.chat_leftover",
            "AI 残留：聊天套话",
            1,
            vec![String::new()],
        )
    }
}

// ---------- en.filler_opener (tier 1) ----------

pub struct FillerOpener;

static FILLER_OPENER: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)(?:it'?s|it is) (?:worth noting|important to note|worth mentioning) that\s+|needless to say,\s*|it goes without saying that\s+",
    )
    .unwrap()
});

impl Rule for FillerOpener {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        FILLER_OPENER
            .find_iter(ctx.text)
            .filter_map(|m| {
                if !ctx.is_sentence_start(m.start()) || ctx.exclusions.code_excluded(m.start()) {
                    return None;
                }
                // the span includes the first letter after the opener so the
                // suggestion can capitalize it
                let after = &ctx.text[m.end()..];
                let (end, suggestions) = match after.chars().next() {
                    Some(c) if c.is_alphabetic() => {
                        let upper: String = c.to_uppercase().collect();
                        (m.end() + c.len_utf8(), vec![upper])
                    }
                    _ => (m.end(), vec![]),
                };
                Some(ctx.make(
                    CAT,
                    "en.filler_opener",
                    "套话开头：可直接删掉",
                    m.start()..end,
                    1,
                    suggestions,
                ))
            })
            .collect()
    }
}

// ---------- en.stock_phrase (tier 1) ----------

pub struct StockPhrase;

static STOCK_PHRASE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)\b(?:delves? into|in today'?s (?:fast-paced|digital|modern) (?:world|age|landscape)|in the ever-evolving (?:world|landscape|realm) of|navigat(?:e|ing) the complexities of|(?:serves|stands) as a testament to|a testament to|plays? a (?:crucial|pivotal|vital|key) role|rich tapestry|tapestry of|unlock(?:s|ing)? the (?:full )?potential|unleash(?:es|ing)? the power|embark(?:s|ing)? on a journey|game[- ]changer)",
    )
    .unwrap()
});

impl Rule for StockPhrase {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        regex_findings(
            ctx,
            &STOCK_PHRASE,
            "en.stock_phrase",
            "AI 高频套语",
            1,
            vec![],
        )
    }
}

// ---------- en.inflated (tier 2) ----------

pub struct Inflated;

static INFLATED: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)\b(?:mark(?:s|ed|ing)? a (?:pivotal|significant|major|new) (?:moment|milestone|turning point|shift|era)|(?:underscor|highlight)(?:es|ed|ing|s)? (?:the|its|their) (?:importance|significance)|setting the stage for|paving the way for|in the realm of|ever-evolving|evolving landscape|indelible mark|deeply rooted)",
    )
    .unwrap()
});

impl Rule for Inflated {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        regex_findings(ctx, &INFLATED, "en.inflated", "夸大措辞", 2, vec![])
    }
}

// ---------- en.vague_attribution (tier 2) ----------

pub struct VagueAttribution;

static VAGUE_ATTRIBUTION: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)\b(?:experts|studies|research|observers|critics|scientists|many) (?:say|believe|suggest|argue|agree|have shown|show)",
    )
    .unwrap()
});

impl Rule for VagueAttribution {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        regex_findings(
            ctx,
            &VAGUE_ATTRIBUTION,
            "en.vague_attribution",
            "模糊归因",
            2,
            vec![],
        )
    }
}

// ---------- en.not_but (tier 2) ----------

pub struct NotBut;

static NOT_BUT: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)\b(?:it'?s|this is|that'?s|it is) not (?:just |only |merely )?(?:about )?[^.!?\n]{1,40}?[,;—–]\s*(?:it'?s|but)\b",
    )
    .unwrap()
});

impl Rule for NotBut {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        regex_findings(
            ctx,
            &NOT_BUT,
            "en.not_but",
            "AI 句式：「not … but」",
            2,
            vec![],
        )
    }
}

// ---------- en.not_only (tier 3) ----------

pub struct NotOnly;

static NOT_ONLY: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)\bnot only [^.!?\n]{1,40}? but (?:also )?").unwrap());

impl Rule for NotOnly {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        regex_findings(
            ctx,
            &NOT_ONLY,
            "en.not_only",
            "AI 句式：「not only … but also」",
            3,
            vec![],
        )
    }
}

// ---------- en.em_dash (tier 2) ----------

pub struct EmDash;

/// ` -- ` with both spaces; `—` needs manual neighbor checks (see below).
static DOUBLE_HYPHEN: LazyLock<Regex> = LazyLock::new(|| Regex::new(r" -- ").unwrap());

/// CJK per RULES.md: U+3000–U+303F, U+4E00–U+9FFF, U+FF00–U+FFEF.
fn is_cjk(c: char) -> bool {
    matches!(
        c,
        '\u{3000}'..='\u{303F}' | '\u{4E00}'..='\u{9FFF}' | '\u{FF00}'..='\u{FFEF}'
    )
}

fn is_space(c: char) -> bool {
    c == ' ' || c == '\t'
}

impl Rule for EmDash {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        let mut out: Vec<Finding> = Vec::new();
        // ASCII " -- "
        for m in DOUBLE_HYPHEN.find_iter(ctx.text) {
            if !ctx.exclusions.code_excluded(m.start())
                && !super::is_numeric_range(ctx.text, m.range())
            {
                out.push(ctx.make(
                    CAT,
                    "en.em_dash",
                    "英文破折号",
                    m.start()..m.end(),
                    2,
                    vec![", ".to_string()],
                ));
            }
        }
        // U+2014 em dash: not adjacent to another `—`, and the nearest
        // non-space character on each side must not be CJK.
        let text = ctx.text;
        for (i, c) in text.char_indices() {
            if c != '—' {
                continue;
            }
            let prev = text[..i].chars().last();
            let next = text[i + c.len_utf8()..].chars().next();
            if prev == Some('—') || next == Some('—') {
                continue;
            }
            if super::is_numeric_range(text, i..i + c.len_utf8()) {
                continue;
            }
            let nearest_left = text[..i].chars().rev().find(|&c| !is_space(c));
            let nearest_right = text[i + c.len_utf8()..].chars().find(|&c| !is_space(c));
            if nearest_left.map(is_cjk).unwrap_or(false)
                || nearest_right.map(is_cjk).unwrap_or(false)
            {
                continue;
            }
            if ctx.exclusions.code_excluded(i) {
                continue;
            }
            // span covers the dash plus the flanking space run
            let mut start = i;
            while start > 0 && text[..start].ends_with(is_space) {
                start = text[..start].char_indices().last().unwrap().0;
            }
            let mut end = i + c.len_utf8();
            while text[end..].starts_with(is_space) {
                end += text[end..].chars().next().unwrap().len_utf8();
            }
            out.push(ctx.make(
                CAT,
                "en.em_dash",
                "英文破折号",
                start..end,
                2,
                vec![", ".to_string()],
            ));
        }
        out
    }
}

// ---------- en.signpost (tier 2 if ≥2 per paragraph, else 3) ----------

pub struct Signpost;

static SIGNPOST: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)\b(?:Moreover|Furthermore|Additionally|In addition|Notably|Importantly|Ultimately|Consequently|In conclusion|In summary|Overall),",
    )
    .unwrap()
});

impl Rule for Signpost {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        let mut out = Vec::new();
        let acronyms = crate::acronyms::ranges(ctx.text);
        for line in ctx.lines {
            let hits: Vec<_> = SIGNPOST
                .find_iter(ctx.line_text(line))
                .filter(|m| {
                    let abs = line.range.start + m.start();
                    ctx.is_sentence_start(abs)
                        && !ctx.exclusions.code_excluded(abs)
                        && !acronyms.iter().any(|r| r.start <= abs && line.range.start + m.end() - 1 <= r.end)
                })
                .collect();
            let tier = if hits.len() >= 2 { 2 } else { 3 };
            for m in hits {
                let abs = line.range.start + m.start();
                out.push(ctx.make(
                    CAT,
                    "en.signpost",
                    "句首路标词",
                    abs..line.range.start + m.end(),
                    tier,
                    vec![],
                ));
            }
        }
        out
    }
}

// ---------- en.ai_vocab (tier 2 if ≥3 distinct per paragraph, else 3) ----------

pub struct AiVocab;

static AI_VOCAB: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)\b(?:delve|tapestry|testament|pivotal|intricate|multifaceted|underscore(?:s|d)?|showcas(?:e|es|ed|ing)|bolster(?:s|ed|ing)?|garner(?:s|ed|ing)?|realm|seamless(?:ly)?|leverag(?:e|es|ed|ing)|foster(?:s|ed|ing)?|vibrant|meticulous(?:ly)?|paramount|nuanced|holistic|synergy|elevat(?:e|es|ed|ing)|commendable|noteworthy|embark(?:s|ed|ing)?)\b",
    )
    .unwrap()
});

impl Rule for AiVocab {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        let mut out = Vec::new();
        let acronyms = crate::acronyms::ranges(ctx.text);
        for line in ctx.lines {
            let hits: Vec<_> = AI_VOCAB
                .find_iter(ctx.line_text(line))
                .filter(|m| {
                    let start = line.range.start + m.start();
                    let end = line.range.start + m.end();
                    !ctx.exclusions.code_excluded(start)
                        && !acronyms.iter().any(|r| r.start <= start && end <= r.end)
                })
                .collect();
            let distinct: HashSet<String> =
                hits.iter().map(|m| m.as_str().to_lowercase()).collect();
            let tier = if distinct.len() >= 3 { 2 } else { 3 };
            for m in hits {
                let abs = line.range.start + m.start();
                out.push(ctx.make(
                    CAT,
                    "en.ai_vocab",
                    "AI 高频词",
                    abs..line.range.start + m.end(),
                    tier,
                    vec![],
                ));
            }
        }
        out
    }
}

pub fn rules() -> Vec<Box<dyn Rule>> {
    vec![
        Box::new(ChatLeftover),
        Box::new(FillerOpener),
        Box::new(StockPhrase),
        Box::new(Inflated),
        Box::new(VagueAttribution),
        Box::new(NotBut),
        Box::new(NotOnly),
        Box::new(EmDash),
        Box::new(Signpost),
        Box::new(AiVocab),
    ]
}
