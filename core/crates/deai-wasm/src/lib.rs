use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct Checker {
    inner: deai_core::Checker,
}

impl Default for Checker {
    fn default() -> Self {
        Self::new()
    }
}

#[wasm_bindgen]
impl Checker {
    #[wasm_bindgen(constructor)]
    pub fn new() -> Self {
        Self {
            inner: deai_core::Checker::new(),
        }
    }

    /// `opts` is a JS object like `{ grammar: true, sensitivity: 2, ... }`.
    /// Missing fields default to on / sensitivity 2. Returns `Finding[]` as
    /// plain objects (with `tier` fields).
    pub fn check(&self, text: &str, opts: JsValue) -> Result<JsValue, JsValue> {
        let opts: deai_core::CheckOptions = serde_wasm_bindgen::from_value(opts)?;
        let findings = self.inner.check(text, &opts);
        Ok(serde_wasm_bindgen::to_value(&findings)?)
    }
}

/// Strip all Markdown residue; `opts` may be `{}` or omitted fields default on.
#[wasm_bindgen]
pub fn strip_markdown(text: &str, opts: JsValue) -> Result<String, JsValue> {
    let opts: deai_core::CheckOptions = serde_wasm_bindgen::from_value(opts)?;
    Ok(deai_core::strip_markdown(text, &opts))
}

/// Apply `replacement` to UTF-16 range `[start, end)` of `text`.
#[wasm_bindgen]
pub fn apply_suggestion(text: &str, start: u32, end: u32, replacement: &str) -> String {
    deai_core::apply_suggestion(text, start, end, replacement)
}

/// Personal-lexicon findings; `entries` is a JS array of
/// `{ kind: "replace"|"avoid"|"keep", term, replacement?, matchKind }`.
#[wasm_bindgen]
pub fn check_personal(text: &str, entries: JsValue) -> Result<JsValue, JsValue> {
    let entries: Vec<deai_core::PersonalEntry> =
        serde_wasm_bindgen::from_value(entries)?;
    Ok(serde_wasm_bindgen::to_value(&deai_core::check_personal(text, &entries))?)
}

/// UTF-16 `[start, end)` ranges covered by `keep` entries (for suppressing
/// other categories' findings).
#[wasm_bindgen]
pub fn personal_keep_ranges(text: &str, entries: JsValue) -> Result<JsValue, JsValue> {
    let entries: Vec<deai_core::PersonalEntry> =
        serde_wasm_bindgen::from_value(entries)?;
    Ok(serde_wasm_bindgen::to_value(&deai_core::personal_keep_ranges(text, &entries))?)
}
