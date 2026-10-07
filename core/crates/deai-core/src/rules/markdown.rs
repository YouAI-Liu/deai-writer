//! Markdown residue rules per RULES.md. Not subject to quote/code exclusions,
//! except that fenced-block interiors are skipped (only the fence lines
//! themselves are checked inside a block).

use std::sync::LazyLock;

use regex::Regex;

use super::{Ctx, Rule};
use crate::{Category, Finding};

const CAT: Category = Category::Markdown;

// ---------- line-level helpers ----------

fn line_finding(
    ctx: &Ctx,
    id: &'static str,
    msg: &'static str,
    tier: u8,
    range: std::ops::Range<usize>,
    suggestions: Vec<String>,
) -> Option<Finding> {
    if ctx.exclusions.md_excluded(range.start) {
        return None;
    }
    Some(ctx.make(CAT, id, msg, range, tier, suggestions))
}

fn line_rules(ctx: &Ctx) -> Vec<Finding> {
    let mut out = Vec::new();
    for line in ctx.lines.iter() {
        let lt = ctx.line_text(line);
        let s = line.range.start;

        // md.code_fence: whole line is a ``` fence
        if CODE_FENCE_LINE.is_match(lt) {
            // include the following separator in the range
            let mut end = line.range.end;
            if end < ctx.text.len() {
                let sep = ctx.text[end..].chars().next().unwrap();
                end += sep.len_utf8();
                if sep == '\r' && ctx.text[end..].starts_with('\n') {
                    end += 1;
                }
            }
            out.extend(line_finding(
                ctx,
                "md.code_fence",
                "Markdown 残留：代码围栏",
                1,
                s..end,
                vec![String::new()],
            ));
            continue; // a fence line is not also a heading/list/etc.
        }

        // md.hr: whole line is ---, *** or ___
        if HR_LINE.is_match(lt) {
            out.extend(line_finding(
                ctx,
                "md.hr",
                "Markdown 残留：分割线",
                1,
                s..line.range.end,
                vec![String::new()],
            ));
            continue; // --- is an hr, never a bullet
        }

        // md.table_row
        if TABLE_ROW.is_match(lt) {
            out.extend(line_finding(
                ctx,
                "md.table_row",
                "Markdown 残留：表格行",
                2,
                s..line.range.end,
                vec![],
            ));
            continue;
        }

        // md.heading
        if let Some(m) = HEADING.find(lt) {
            out.extend(line_finding(
                ctx,
                "md.heading",
                "Markdown 残留：标题井号",
                1,
                s + m.start()..s + m.end(),
                vec![String::new()],
            ));
        }

        // md.blockquote
        if let Some(m) = BLOCKQUOTE.find(lt) {
            out.extend(line_finding(
                ctx,
                "md.blockquote",
                "Markdown 残留：引用符",
                1,
                s + m.start()..s + m.end(),
                vec![String::new()],
            ));
        }

        // md.list_bullet (never when the line is an hr — handled above)
        if let Some(m) = LIST_BULLET.find(lt) {
            out.extend(line_finding(
                ctx,
                "md.list_bullet",
                "Markdown 残留：列表符",
                2,
                s + m.start()..s + m.end(),
                vec![String::new()],
            ));
        }
    }
    out
}

static CODE_FENCE_LINE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s*```[\w+-]*\s*$").unwrap());
static HR_LINE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s*(?:-{3,}|\*{3,}|_{3,})\s*$").unwrap());
static TABLE_ROW: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^\s*\|.*\|\s*$").unwrap());
static HEADING: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^#{1,6}[ \t]+").unwrap());
static BLOCKQUOTE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^>[ \t]?").unwrap());
static LIST_BULLET: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[ \t]*[-*+][ \t]+").unwrap());

// ---------- inline rules ----------

fn re_findings(
    ctx: &Ctx,
    re: &Regex,
    id: &'static str,
    msg: &'static str,
    tier: u8,
    suggestion: impl Fn(&regex::Captures) -> Vec<String>,
    extra_filter: impl Fn(&Ctx, &regex::Captures) -> bool,
) -> Vec<Finding> {
    re.captures_iter(ctx.text)
        .filter(|c| extra_filter(ctx, c))
        .filter(|c| !ctx.exclusions.md_excluded(c.get(0).unwrap().start()))
        .map(|c| {
            let m = c.get(0).unwrap();
            ctx.make(CAT, id, msg, m.start()..m.end(), tier, suggestion(&c))
        })
        .collect()
}

fn no_extra(_: &Ctx, _: &regex::Captures) -> bool {
    true
}

// md.bold / md.strike / md.inline_code — suggestion is capture group 1
fn g1(c: &regex::Captures) -> Vec<String> {
    vec![c.get(1).unwrap().as_str().to_string()]
}

pub struct MdBold;
static BOLD: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\*\*([^*\n]+?)\*\*|__([^_\n]+?)__").unwrap());
impl Rule for MdBold {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        re_findings(
            ctx,
            &BOLD,
            "md.bold",
            "Markdown 残留：加粗",
            1,
            |c| {
                let g = c.get(1).or_else(|| c.get(2)).unwrap();
                vec![g.as_str().to_string()]
            },
            no_extra,
        )
    }
}

pub struct MdStrike;
static STRIKE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"~~([^~\n]+?)~~").unwrap());
impl Rule for MdStrike {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        re_findings(
            ctx,
            &STRIKE,
            "md.strike",
            "Markdown 残留：删除线",
            1,
            g1,
            no_extra,
        )
    }
}

pub struct MdInlineCode;
static INLINE_CODE_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"`([^`\n]+)`").unwrap());
impl Rule for MdInlineCode {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        re_findings(
            ctx,
            &INLINE_CODE_RE,
            "md.inline_code",
            "Markdown 残留：行内代码",
            1,
            g1,
            no_extra,
        )
    }
}

// md.link / md.image
pub struct MdLink;
static LINK: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\[([^\]\n]+)\]\(([^)\s]+)\)").unwrap());
impl Rule for MdLink {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        re_findings(
            ctx,
            &LINK,
            "md.link",
            "Markdown 残留：链接",
            1,
            |c| {
                let label = c.get(1).unwrap().as_str();
                let url = c.get(2).unwrap().as_str();
                vec![
                    label.to_string(),
                    format!("{} ({})", label, url),
                    url.to_string(),
                ]
            },
            |ctx, c| {
                // previous char must not be `!` (that's md.image)
                let s = c.get(0).unwrap().start();
                !ctx.text[..s].ends_with('!')
            },
        )
    }
}

pub struct MdImage;
static IMAGE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"!\[([^\]\n]*)\]\([^)\n]+\)").unwrap());
impl Rule for MdImage {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        re_findings(
            ctx,
            &IMAGE,
            "md.image",
            "Markdown 残留：图片",
            1,
            |c| vec![c.get(1).unwrap().as_str().to_string()],
            no_extra,
        )
    }
}

// md.italic — neighbor checks done by hand (regex crate has no lookaround)
pub struct MdItalic;
static ITALIC: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\*([^*\n]+)\*").unwrap());
impl Rule for MdItalic {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        re_findings(
            ctx,
            &ITALIC,
            "md.italic",
            "Markdown 残留：斜体",
            2,
            g1,
            |ctx, c| {
                let m = c.get(0).unwrap();
                let inner = c.get(1).unwrap().as_str();
                // X may not start or end with whitespace
                if inner != inner.trim() {
                    return false;
                }
                fn bad(c: char) -> bool {
                    c == '*' || c.is_alphanumeric()
                }
                if ctx.text[..m.start()]
                    .chars()
                    .last()
                    .map(bad)
                    .unwrap_or(false)
                {
                    return false;
                }
                if ctx.text[m.end()..].chars().next().map(bad).unwrap_or(false) {
                    return false;
                }
                true
            },
        )
    }
}

// md.escape
pub struct MdEscape;
static ESCAPE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\\([*_#`>\[\]~])").unwrap());
impl Rule for MdEscape {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        re_findings(
            ctx,
            &ESCAPE,
            "md.escape",
            "Markdown 残留：转义符",
            2,
            g1,
            no_extra,
        )
    }
}

/// All line-level md rules in one pass (the line kinds are mutually
/// exclusive, so a single rule struct is fine).
pub struct MdLines;
impl Rule for MdLines {
    fn category(&self) -> Category {
        CAT
    }
    fn check(&self, ctx: &Ctx) -> Vec<Finding> {
        line_rules(ctx)
    }
}

pub fn rules() -> Vec<Box<dyn Rule>> {
    vec![
        Box::new(MdBold),
        Box::new(MdStrike),
        Box::new(MdLines),
        Box::new(MdInlineCode),
        Box::new(MdLink),
        Box::new(MdImage),
        Box::new(MdItalic),
        Box::new(MdEscape),
    ]
}
