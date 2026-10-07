//! Rule implementations per `RULES.md`. Each rule is a unit struct
//! implementing `Rule`; `all()` returns them so that within a category the
//! order matches the spec tables (used by dedupe tie-breaking).

pub mod en;
pub mod markdown;
pub mod zh;

use std::ops::Range;

use crate::offsets::Utf16Map;
use crate::text::{Exclusions, Line};
use crate::{Category, Finding};

/// Shared context handed to every rule during a `check` pass.
pub struct Ctx<'a> {
    pub text: &'a str,
    pub map: &'a Utf16Map,
    pub lines: &'a [Line],
    pub exclusions: &'a Exclusions,
}

impl Ctx<'_> {
    /// Byte range of the whole line containing `pos` (binary search — lines
    /// are ordered and non-overlapping).
    pub fn line_at(&self, pos: usize) -> Option<&Line> {
        let i = self
            .lines
            .partition_point(|l| l.range.start <= pos)
            .checked_sub(1)?;
        let line = &self.lines[i];
        (pos <= line.range.end).then_some(line)
    }

    pub fn line_text(&self, line: &Line) -> &str {
        &self.text[line.range.clone()]
    }

    /// `pos` is the start of a sentence (line start or right after a
    /// terminator + closers + whitespace).
    pub fn is_sentence_start(&self, pos: usize) -> bool {
        self.line_at(pos)
            .map(|l| l.sentences.iter().any(|s| s.start == pos))
            .unwrap_or(false)
    }

    /// `pos` is the first sentence of its line/paragraph.
    pub fn is_para_start(&self, pos: usize) -> bool {
        self.line_at(pos)
            .and_then(|l| l.sentences.first())
            .map(|s| s.start == pos)
            .unwrap_or(false)
    }

    pub fn make(
        &self,
        category: Category,
        rule_id: &'static str,
        message: &'static str,
        range: Range<usize>,
        tier: u8,
        suggestions: Vec<String>,
    ) -> Finding {
        let (start, end) = self.map.range_bytes(range.start, range.end);
        Finding {
            category,
            rule_id: rule_id.to_string(),
            message: message.to_string(),
            start,
            end,
            suggestions,
            tier,
        }
    }
}

pub trait Rule: Send + Sync {
    fn category(&self) -> Category;
    fn check(&self, ctx: &Ctx) -> Vec<Finding>;
}

/// All rules, ordered so that each category's entries appear in spec order.
pub fn all() -> Vec<Box<dyn Rule>> {
    let mut v: Vec<Box<dyn Rule>> = Vec::new();
    v.extend(zh::rules());
    v.extend(en::rules());
    v.extend(markdown::rules());
    v
}

pub fn markdown_rules() -> Vec<Box<dyn Rule>> {
    markdown::rules()
}
