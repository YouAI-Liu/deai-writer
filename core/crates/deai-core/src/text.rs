//! Paragraph/line segmentation, sentence-start detection, and exclusion zones
//! per RULES.md 通用约定.
//!
//! "段落" per spec = text split on \n, \r, \u2028, \u2029 — i.e. a line
//! (Word emits LF, TextEdit emits CR).

use std::ops::Range;
use std::sync::LazyLock;

use regex::Regex;

/// A paragraph/line: byte range excluding the trailing separator.
pub struct Line {
    pub range: Range<usize>,
    /// Sentences inside this line; `start` = first content char (after leading
    /// whitespace), `end` = just past the terminator and any closing quotes.
    pub sentences: Vec<Range<usize>>,
}

const TERMINATORS: &[char] = &['。', '！', '？', '!', '?'];
const CLOSERS: &[char] = &['”', '」', '』', '）'];
const SEPARATORS: &[char] = &['\n', '\r', '\u{2028}', '\u{2029}'];

pub fn lines(text: &str) -> Vec<Line> {
    let mut out = Vec::new();
    let mut start = 0usize;
    for (i, c) in text.char_indices() {
        if SEPARATORS.contains(&c) {
            out.push(mk_line(text, start, i));
            start = i + c.len_utf8();
        }
    }
    out.push(mk_line(text, start, text.len()));
    out
}

fn mk_line(text: &str, start: usize, end: usize) -> Line {
    Line {
        range: start..end,
        sentences: sentences(text, start, end),
    }
}

/// Sentence ranges inside `text[start..end]`. A new sentence begins at the
/// first non-whitespace char after a terminator plus any closers.
fn sentences(text: &str, start: usize, end: usize) -> Vec<Range<usize>> {
    let chars: Vec<(usize, char)> = text[start..end]
        .char_indices()
        .map(|(o, c)| (start + o, c))
        .collect();
    let mut out = Vec::new();
    let mut i = 0usize;
    // first sentence starts at the first content char of the line
    while i < chars.len() && chars[i].1.is_whitespace() {
        i += 1;
    }
    let mut sent_start = if i < chars.len() { chars[i].0 } else { end };
    while i < chars.len() {
        let (_, c) = chars[i];
        if TERMINATORS.contains(&c) {
            // consume the terminator run, trailing closers, and whitespace
            let mut j = i + 1;
            while j < chars.len()
                && (TERMINATORS.contains(&chars[j].1) || CLOSERS.contains(&chars[j].1))
            {
                j += 1;
            }
            let sent_end = if j < chars.len() { chars[j].0 } else { end };
            out.push(sent_start..sent_end);
            while j < chars.len() && chars[j].1.is_whitespace() {
                j += 1;
            }
            sent_start = if j < chars.len() { chars[j].0 } else { end };
            i = j;
        } else {
            i += 1;
        }
    }
    if sent_start < end {
        out.push(sent_start..end);
    }
    out
}

/// List-item lines (L1 in RULES.md).
static LIST_ITEM: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^\s*(?:[-*+•·]\s|\d+[.、)）]\s?|[（(]?[一二三四五六七八九十]+[、)）])").unwrap()
});

pub fn is_list_item(line_text: &str) -> bool {
    LIST_ITEM.is_match(line_text)
}

pub fn is_heading_line(line_text: &str) -> bool {
    line_text.trim_start().starts_with('#')
}

/// Exclusion zones, in byte offsets.
///
/// - `fenced`: whole ``` code blocks including the fence lines — skipped by all
///   AI-tone rules.
/// - `fence_interior`: content between the fence lines — only place Markdown
///   rules stay silent.
/// - `inline_code`: `` `…` `` spans outside fenced blocks.
/// - `quotes`: `“…”` `「…」` `『…』` and paired `"…"` — zh rules only.
pub struct Exclusions {
    pub fenced: Vec<Range<usize>>,
    pub fence_interior: Vec<Range<usize>>,
    pub inline_code: Vec<Range<usize>>,
    pub quotes: Vec<Range<usize>>,
}

/// `ranges` are built in order; binary-search for a containing range.
fn contains(ranges: &[Range<usize>], pos: usize) -> bool {
    let i = ranges.partition_point(|r| r.start <= pos);
    if i == 0 {
        return false;
    }
    pos < ranges[i - 1].end
}

impl Exclusions {
    pub fn build(text: &str, lines: &[Line]) -> Self {
        // fenced blocks: a line whose trimmed text starts with ``` toggles state
        let mut fenced = Vec::new();
        let mut fence_interior = Vec::new();
        let mut open: Option<&Line> = None;
        for line in lines {
            let lt = &text[line.range.clone()];
            if lt.trim_start().starts_with("```") {
                match open {
                    None => open = Some(line),
                    Some(o) => {
                        fenced.push(o.range.start..line.range.end);
                        fence_interior.push(o.range.end..line.range.start);
                        open = None;
                    }
                }
            }
        }
        if let Some(o) = open {
            fenced.push(o.range.start..text.len());
            fence_interior.push(o.range.end..text.len());
        }

        // inline code outside fenced blocks; backticks inside fenced text don't count
        let inline_code: Vec<Range<usize>> = INLINE_CODE
            .find_iter(text)
            .map(|m| m.start()..m.end())
            .filter(|r| !contains(&fenced, r.start))
            .collect();

        // quote pairs: quote chars inside fenced/inline code don't pair
        let mut quotes = Vec::new();
        for (open_c, close_c) in [('“', '”'), ('「', '」'), ('『', '』')] {
            let mut start = None;
            for (i, c) in text.char_indices() {
                if contains(&fenced, i) || contains(&inline_code, i) {
                    continue;
                }
                if c == open_c && start.is_none() {
                    start = Some(i);
                } else if c == close_c {
                    if let Some(s) = start.take() {
                        quotes.push(s..i + c.len_utf8());
                    }
                }
            }
        }
        let mut start = None;
        for (i, c) in text.char_indices() {
            if c != '"' || contains(&fenced, i) || contains(&inline_code, i) {
                continue;
            }
            match start {
                None => start = Some(i),
                Some(s) => {
                    quotes.push(s..i + 1);
                    start = None;
                }
            }
        }

        // keep each set sorted and non-overlapping so `contains` can
        // binary-search safely
        fn normalize(mut v: Vec<Range<usize>>) -> Vec<Range<usize>> {
            v.sort_by_key(|r| r.start);
            let mut out: Vec<Range<usize>> = Vec::with_capacity(v.len());
            for r in v {
                match out.last_mut() {
                    Some(last) if r.start <= last.end => last.end = last.end.max(r.end),
                    _ => out.push(r),
                }
            }
            out
        }

        Self {
            fenced: normalize(fenced),
            fence_interior: normalize(fence_interior),
            inline_code: normalize(inline_code),
            quotes: normalize(quotes),
        }
    }

    /// AI-tone rules (zh + en): fenced blocks and inline code.
    pub fn code_excluded(&self, pos: usize) -> bool {
        contains(&self.fenced, pos) || contains(&self.inline_code, pos)
    }

    /// zh rules additionally skip quoted text.
    pub fn zh_excluded(&self, pos: usize) -> bool {
        self.code_excluded(pos) || contains(&self.quotes, pos)
    }

    /// Markdown rules: only fenced-block interiors are off-limits (the fence
    /// lines themselves are still checked).
    pub fn md_excluded(&self, pos: usize) -> bool {
        contains(&self.fence_interior, pos)
    }
}

static INLINE_CODE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"`[^`\n]+`").unwrap());
