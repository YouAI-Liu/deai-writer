uniffi::setup_scaffolding!();

#[derive(uniffi::Enum)]
pub enum Category {
    Grammar,
    AiToneEn,
    AiToneZh,
    Markdown,
}

#[derive(uniffi::Record)]
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

#[derive(uniffi::Record)]
pub struct CheckOptions {
    pub grammar: bool,
    pub ai_tone_en: bool,
    pub ai_tone_zh: bool,
    pub markdown: bool,
    /// 1..=3; findings with `tier <= sensitivity` are returned.
    pub sensitivity: u8,
}

impl From<CheckOptions> for deai_core::CheckOptions {
    fn from(o: CheckOptions) -> Self {
        deai_core::CheckOptions {
            grammar: o.grammar,
            ai_tone_en: o.ai_tone_en,
            ai_tone_zh: o.ai_tone_zh,
            markdown: o.markdown,
            sensitivity: o.sensitivity,
        }
    }
}

impl From<deai_core::Finding> for Finding {
    fn from(f: deai_core::Finding) -> Self {
        Finding {
            category: match f.category {
                deai_core::Category::Grammar => Category::Grammar,
                deai_core::Category::AiToneEn => Category::AiToneEn,
                deai_core::Category::AiToneZh => Category::AiToneZh,
                deai_core::Category::Markdown => Category::Markdown,
            },
            rule_id: f.rule_id,
            message: f.message,
            start: f.start,
            end: f.end,
            suggestions: f.suggestions,
            tier: f.tier,
        }
    }
}

#[derive(uniffi::Object)]
pub struct Checker {
    inner: deai_core::Checker,
}

impl Default for Checker {
    fn default() -> Self {
        Self::new()
    }
}

#[uniffi::export]
impl Checker {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            inner: deai_core::Checker::new(),
        }
    }

    pub fn check(&self, text: String, opts: CheckOptions) -> Vec<Finding> {
        self.inner
            .check(&text, &opts.into())
            .into_iter()
            .map(Finding::from)
            .collect()
    }
}

/// Strip all Markdown residue (tiers 1-2, ignoring sensitivity).
#[uniffi::export]
pub fn strip_markdown(text: String, opts: CheckOptions) -> String {
    deai_core::strip_markdown(&text, &opts.into())
}

/// Apply `replacement` to UTF-16 range `[start, end)` of `text`.
#[uniffi::export]
pub fn apply_suggestion(text: String, start: u32, end: u32, replacement: String) -> String {
    deai_core::apply_suggestion(&text, start, end, &replacement)
}
