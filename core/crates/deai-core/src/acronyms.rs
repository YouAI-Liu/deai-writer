use std::ops::Range;
use std::sync::LazyLock;

use regex::Regex;

use crate::offsets::Utf16Map;
use crate::Finding;

// Cased letters keep adjacent Chinese prose outside the acronym token.
static TOKENS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"[\p{Lu}\p{Ll}\p{Lt}\p{Nd}&-]+").unwrap());

fn is_acronym(token: &str) -> bool {
    let base = token.strip_suffix('s').unwrap_or(token);
    base.chars().count() >= 2
        && base.chars().any(char::is_uppercase)
        && base
            .chars()
            .all(|c| c.is_uppercase() || c.is_numeric() || matches!(c, '-' | '&'))
}

pub fn ranges(text: &str) -> Vec<Range<usize>> {
    TOKENS
        .find_iter(text)
        .filter(|m| is_acronym(m.as_str()))
        .map(|m| m.range())
        .collect()
}

/// Check the replaced span together with any partially covered acronym.
/// Markdown wrappers and opener deletions can change while the token stays intact.
pub fn preserves(text: &str, map: &Utf16Map, acronyms: &[Range<usize>], f: &Finding) -> bool {
    let start = map.byte_of_utf16(f.start);
    let end = map.byte_of_utf16(f.end);
    let affected: Vec<_> = acronyms
        .iter()
        .filter(|r| r.start < end && start < r.end)
        .collect();
    if affected.is_empty() {
        return true;
    }
    if f.rule_id == "harper.Spelling" {
        return false;
    }
    if f.suggestions.is_empty() {
        return f.category == crate::Category::Grammar
            || !affected.iter().any(|r| r.start <= start && end <= r.end);
    }
    let left = start.min(affected.first().unwrap().start);
    let right = end.max(affected.last().unwrap().end);
    f.suggestions.iter().all(|suggestion| {
        let rewritten = format!("{}{}{}", &text[left..start], suggestion, &text[end..right]);
        let mut tokens: Vec<_> = TOKENS.find_iter(&rewritten).map(|m| m.as_str()).collect();
        affected.iter().all(|r| {
            let original = &text[(*r).clone()];
            if let Some(i) = tokens.iter().position(|t| *t == original) {
                tokens.remove(i);
                true
            } else {
                false
            }
        })
    })
}
