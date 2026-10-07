pub mod offsets;
mod rules;
mod text;
pub mod utf16;

use std::sync::Mutex;

use harper_core::linting::{LintGroup, Linter, Suggestion};
use harper_core::parsers::PlainEnglish;
use harper_core::spell::FstDictionary;
use harper_core::{Dialect, Document};
use serde::{Deserialize, Serialize};

use offsets::Utf16Map;
use rules::{Ctx, Rule};
use text::Exclusions;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Category {
    Grammar,
    AiToneEn,
    AiToneZh,
    Markdown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Finding {
    pub category: Category,
    pub rule_id: String,
    pub message: String,
    /// UTF-16 code unit offset, inclusive.
    pub start: u32,
    /// UTF-16 code unit offset, exclusive.
    pub end: u32,
    /// Replacement texts for `[start, end)`; may be empty.
    pub suggestions: Vec<String>,
    /// Confidence tier: 1 = high, 2 = standard, 3 = sensitive.
    pub tier: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct CheckOptions {
    pub grammar: bool,
    pub ai_tone_en: bool,
    pub ai_tone_zh: bool,
    pub markdown: bool,
    /// 1..=3; findings with `tier <= sensitivity` are returned.
    pub sensitivity: u8,
}

impl Default for CheckOptions {
    fn default() -> Self {
        Self {
            grammar: true,
            ai_tone_en: true,
            ai_tone_zh: true,
            markdown: true,
            sensitivity: 2,
        }
    }
}

impl CheckOptions {
    fn enabled(&self, category: Category) -> bool {
        match category {
            Category::Grammar => self.grammar,
            Category::AiToneEn => self.ai_tone_en,
            Category::AiToneZh => self.ai_tone_zh,
            Category::Markdown => self.markdown,
        }
    }

    fn sensitivity(&self) -> u8 {
        self.sensitivity.clamp(1, 3)
    }
}

/// Context shared across all rules in one check pass.
fn make_ctx<'a>(
    text: &'a str,
    map: &'a Utf16Map,
    lines: &'a [text::Line],
    exclusions: &'a Exclusions,
) -> Ctx<'a> {
    Ctx {
        text,
        map,
        lines,
        exclusions,
    }
}

/// Explicit supersede pairs per RULES.md 通用约定·去重: when two findings
/// overlap, `(winner, loser)` drops the loser. All other overlapping findings
/// are kept; different categories never dedupe against each other.
static SUPERSEDES: &[(&str, &str)] = &[
    ("zh.prompt_colon", "zh.this_means"),
    ("zh.zero_anaphor", "zh.this_means"),
    ("zh.banned_opener", "zh.zero_anaphor"),
    ("zh.fanan", "zh.fanan_loose"),
    ("zh.zero_anaphor", "zh.lead_connective"),
    ("en.chat_leftover", "en.ai_vocab"),
    ("en.filler_opener", "en.ai_vocab"),
    ("en.stock_phrase", "en.ai_vocab"),
    ("en.inflated", "en.ai_vocab"),
    ("en.stock_phrase", "en.inflated"),
    ("en.not_but", "en.not_only"),
    ("md.hr", "md.list_bullet"),
    ("md.image", "md.link"),
];

fn overlaps(a: &Finding, b: &Finding) -> bool {
    a.start < b.end && b.start < a.end
}

/// Dedupe per RULES.md:
/// 1. same category + identical span -> keep lower tier, then earlier rule
///    (`order` = position in the spec table);
/// 2. overlapping findings survive except the explicit supersede pairs.
fn dedupe(mut items: Vec<(usize, Finding)>) -> Vec<Finding> {
    items.sort_by_key(|(order, f)| (f.start, f.end, f.tier, *order));
    // identical-span, same category: the sort above puts the winner first
    let mut kept: Vec<(usize, Finding)> = Vec::with_capacity(items.len());
    for it in items {
        let dup = kept.iter().any(|(_, a)| {
            a.category == it.1.category && a.start == it.1.start && a.end == it.1.end
        });
        if !dup {
            kept.push(it);
        }
    }
    // supersede pairs on overlap
    let mut dropped = vec![false; kept.len()];
    for i in 0..kept.len() {
        for j in 0..kept.len() {
            if i == j || dropped[j] {
                continue;
            }
            let (a, b) = (&kept[i].1, &kept[j].1);
            if overlaps(a, b)
                && SUPERSEDES
                    .iter()
                    .any(|&(w, l)| w == a.rule_id && l == b.rule_id)
            {
                dropped[j] = true;
            }
        }
    }
    kept.into_iter()
        .zip(dropped)
        .filter_map(|((_, f), d)| (!d).then_some(f))
        .collect()
}

fn run_rules(text: &str, rules: &[Box<dyn Rule>]) -> Vec<(usize, Finding)> {
    let map = Utf16Map::new(text);
    let lines = text::lines(text);
    let exclusions = Exclusions::build(text, &lines);
    let ctx = make_ctx(text, &map, &lines, &exclusions);
    let mut out = Vec::new();
    for (i, rule) in rules.iter().enumerate() {
        for f in rule.check(&ctx) {
            out.push((i, f));
        }
    }
    out
}

pub struct Checker {
    /// harper's `Linter::lint` takes `&mut self`.
    linter: Mutex<LintGroup>,
    rules: Vec<Box<dyn Rule>>,
}

impl Default for Checker {
    fn default() -> Self {
        Self::new()
    }
}

impl Checker {
    pub fn new() -> Self {
        let dict = FstDictionary::curated();
        let checker = Self {
            linter: Mutex::new(LintGroup::new_curated(dict, Dialect::American)),
            rules: rules::all(),
        };
        // Compile every rule regex once here (LazyLock defers compilation to
        // first use) so the first real `check` does not pay for it.
        let warm = CheckOptions {
            grammar: false,
            ai_tone_en: true,
            ai_tone_zh: true,
            markdown: true,
            sensitivity: 3,
        };
        let _ = checker.check("warmup，test **x** # h", &warm);
        checker
    }

    pub fn check(&self, text: &str, opts: &CheckOptions) -> Vec<Finding> {
        let map = Utf16Map::new(text);
        let lines = text::lines(text);
        let exclusions = Exclusions::build(text, &lines);
        let ctx = make_ctx(text, &map, &lines, &exclusions);

        // gather per-category, tagged with rule order
        let mut per_cat: [Vec<(usize, Finding)>; 4] = Default::default();
        let idx = |c: Category| match c {
            Category::Grammar => 0,
            Category::AiToneEn => 1,
            Category::AiToneZh => 2,
            Category::Markdown => 3,
        };

        for (i, rule) in self.rules.iter().enumerate() {
            if !opts.enabled(rule.category()) {
                continue;
            }
            for f in rule.check(&ctx) {
                per_cat[idx(rule.category())].push((i, f));
            }
        }
        if opts.grammar {
            for f in self.grammar_findings(text, &map) {
                per_cat[idx(Category::Grammar)].push((0, f));
            }
        }

        let sensitivity = opts.sensitivity();
        let mut findings: Vec<Finding> = per_cat
            .into_iter()
            .flat_map(dedupe)
            .filter(|f| f.tier <= sensitivity)
            .collect();
        findings.sort_by_key(|f| (f.start, f.end));
        findings
    }

    fn grammar_findings(&self, text: &str, map: &Utf16Map) -> Vec<Finding> {
        let doc = Document::new_curated(text, &PlainEnglish);
        let source: Vec<char> = text.chars().collect();
        let mut linter = self.linter.lock().unwrap();
        linter
            .lint(&doc)
            .into_iter()
            .map(|lint| {
                let (start, end) = map.range_chars(lint.span.start, lint.span.end);
                let suggestions = lint
                    .suggestions
                    .iter()
                    .map(|s| match s {
                        Suggestion::ReplaceWith(chars) => chars.iter().collect::<String>(),
                        Suggestion::Remove => String::new(),
                        // Expressible as "keep the span, then append".
                        Suggestion::InsertAfter(chars) => format!(
                            "{}{}",
                            source[lint.span.start..lint.span.end.min(source.len())]
                                .iter()
                                .collect::<String>(),
                            chars.iter().collect::<String>()
                        ),
                    })
                    .collect();
                Finding {
                    category: Category::Grammar,
                    rule_id: format!("harper.{:?}", lint.lint_kind),
                    message: lint.message.clone(),
                    start,
                    end,
                    suggestions,
                    tier: 1,
                }
            })
            .collect()
    }
}

/// Apply `replacement` to the UTF-16 range `[start, end)` of `text`.
pub fn apply_suggestion(text: &str, start: u32, end: u32, replacement: &str) -> String {
    let map = Utf16Map::new(text);
    let s = map.byte_of_utf16(start);
    let e = map.byte_of_utf16(end).max(s);
    let mut out = String::with_capacity(text.len() + replacement.len());
    out.push_str(&text[..s]);
    out.push_str(replacement);
    out.push_str(&text[e.min(text.len())..]);
    out
}

/// Remove Markdown residue per RULES.md: in each round take all markdown
/// findings (ignoring `sensitivity`), select the non-overlapping ones, and
/// apply `suggestions[0]` back-to-front; findings without suggestions are
/// skipped. Re-check and repeat until nothing applicable remains or 4 rounds
/// have passed — nested markup like `**[x](u)**` needs multiple passes.
pub fn strip_markdown(text: &str, opts: &CheckOptions) -> String {
    if !opts.markdown {
        return text.to_string();
    }
    let rules = rules::markdown_rules();
    let mut out = text.to_string();
    for _ in 0..4 {
        let deduped = dedupe(run_rules(&out, &rules));
        // select non-overlapping findings with a suggestion, sorted by start
        let mut sorted: Vec<Finding> = deduped
            .into_iter()
            .filter(|f| !f.suggestions.is_empty())
            .collect();
        sorted.sort_by_key(|f| (f.start, f.end));
        let mut selected: Vec<Finding> = Vec::with_capacity(sorted.len());
        for f in sorted {
            if selected.iter().any(|a| overlaps(a, &f)) {
                continue;
            }
            selected.push(f);
        }
        if selected.is_empty() {
            break;
        }
        let map = Utf16Map::new(&out);
        for f in selected.iter().rev() {
            let s = map.byte_of_utf16(f.start);
            let e = map.byte_of_utf16(f.end).max(s);
            out.replace_range(s..e.min(out.len()), &f.suggestions[0]);
        }
    }
    out
}

#[cfg(test)]
mod tests;
