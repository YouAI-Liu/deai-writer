//! Personal lexicon checks: user-supplied `replace` / `avoid` / `keep` terms.
//!
//! Matching is character-aligned so UTF-16 offsets stay exact:
//! - `Exact`: literal substring match.
//! - `CaseInsensitive`: per-char Unicode lowercase equality (chars compare
//!   1:1, so a lowercase expansion like 'İ' can't shift later offsets).
//! - `WholeWord`: literal match plus an ASCII-alphanumeric boundary on both
//!   sides. CJK terms therefore behave like `Exact` — a CJK char is never
//!   ASCII-alnum, so the boundary test can only exclude matches embedded in
//!   latin/digit runs.
//!
//! Overlapping occurrences resolve by longer term first, then earlier entry.

use serde::{Deserialize, Serialize};

use crate::utf16;
use crate::{Category, Finding};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PersonalKind {
    Replace,
    Avoid,
    Keep,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PersonalMatch {
    Exact,
    CaseInsensitive,
    WholeWord,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PersonalEntry {
    pub kind: PersonalKind,
    pub term: String,
    pub replacement: Option<String>,
    pub match_kind: PersonalMatch,
}

fn lower_eq(a: char, b: char) -> bool {
    if a == b {
        return true;
    }
    a.to_lowercase().eq(b.to_lowercase())
}

fn boundary_ok(chars: &[char], start: usize, end: usize) -> bool {
    let before_ok = start == 0 || !chars[start - 1].is_ascii_alphanumeric();
    let after_ok = end == chars.len() || !chars[end].is_ascii_alphanumeric();
    before_ok && after_ok
}

/// Char-indexed ranges where `term` occurs in `chars` under `match_kind`.
fn occurrences(
    chars: &[char],
    term: &[char],
    match_kind: PersonalMatch,
) -> Vec<(usize, usize)> {
    if term.is_empty() || term.len() > chars.len() {
        return Vec::new();
    }
    let ci = match_kind == PersonalMatch::CaseInsensitive;
    let mut out = Vec::new();
    for i in 0..=chars.len() - term.len() {
        let hit = if ci {
            chars[i..i + term.len()]
                .iter()
                .zip(term.iter())
                .all(|(&c, &t)| lower_eq(c, t))
        } else {
            chars[i..i + term.len()] == *term
        };
        if hit {
            let end = i + term.len();
            if match_kind != PersonalMatch::WholeWord || boundary_ok(chars, i, end) {
                out.push((i, end));
            }
        }
    }
    out
}

/// Occurrences of entries whose kind is in `kinds`, as UTF-16 `(start, end)`
/// pairs, overlap-resolved (longer term wins, then earlier entry) and sorted
/// by start. `(entry_index, start, end)` per hit.
pub fn scan(text: &str, entries: &[PersonalEntry], kinds: &[PersonalKind]) -> Vec<(usize, u32, u32)> {
    let chars: Vec<char> = text.chars().collect();
    let mut candidates: Vec<(usize, usize, usize)> = Vec::new(); // entry, cs, ce
    for (ei, entry) in entries.iter().enumerate() {
        if entry.term.is_empty() || !kinds.contains(&entry.kind) {
            continue;
        }
        let term: Vec<char> = entry.term.chars().collect();
        for (s, e) in occurrences(&chars, &term, entry.match_kind) {
            candidates.push((ei, s, e));
        }
    }
    // longer span wins, then earlier entry, then earlier position
    candidates.sort_by(|a, b| {
        (b.2 - b.1).cmp(&(a.2 - a.1)).then(a.0.cmp(&b.0)).then(a.1.cmp(&b.1))
    });
    let mut picked: Vec<(usize, usize, usize)> = Vec::new();
    for c in candidates {
        if picked.iter().any(|p| p.1 < c.2 && c.1 < p.2) {
            continue;
        }
        picked.push(c);
    }
    picked.sort_by_key(|p| p.1);
    picked
        .into_iter()
        .map(|(ei, s, e)| {
            (
                ei,
                utf16::char_to_utf16(text, s),
                utf16::char_to_utf16(text, e),
            )
        })
        .collect()
}

/// UTF-16 ranges covered by `keep` entries — callers use these to suppress
/// findings from other categories (and as the lexicon side of "保留词").
pub fn keep_ranges(text: &str, entries: &[PersonalEntry]) -> Vec<(u32, u32)> {
    scan(text, entries, &[PersonalKind::Keep])
        .into_iter()
        .map(|(_, s, e)| (s, e))
        .collect()
}

/// Findings for `replace`/`avoid` entries (`keep` never produces findings).
/// Tier 1: user-authored rules are always high-confidence.
pub fn check_personal(text: &str, entries: &[PersonalEntry]) -> Vec<Finding> {
    scan(text, entries, &[PersonalKind::Replace, PersonalKind::Avoid])
        .into_iter()
        .map(|(ei, start, end)| {
            let entry = &entries[ei];
            let (rule_id, message, suggestions) = match entry.kind {
                PersonalKind::Replace => (
                    "personal.replace",
                    format!(
                        "个人偏好：用「{}」代替「{}」",
                        entry.replacement.as_deref().unwrap_or(""),
                        entry.term
                    ),
                    vec![entry.replacement.clone().unwrap_or_default()],
                ),
                PersonalKind::Avoid => (
                    "personal.avoid",
                    format!("个人偏好：避免使用「{}」", entry.term),
                    Vec::new(),
                ),
                PersonalKind::Keep => unreachable!("keep entries produce no findings"),
            };
            Finding {
                category: Category::Personal,
                rule_id: rule_id.to_string(),
                message,
                start,
                end,
                suggestions,
                tier: 1,
            }
        })
        .collect()
}
