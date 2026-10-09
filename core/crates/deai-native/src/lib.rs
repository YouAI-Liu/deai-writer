use std::ffi::{c_char, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::OnceLock;

use deai_core::{CheckOptions, Checker, Finding, PersonalEntry};
use serde::{Deserialize, Serialize};

const MAX_REQUEST_BYTES: usize = 4_000_000;
const MAX_TEXT_UNITS: usize = 100_000;
static CHECKER: OnceLock<Checker> = OnceLock::new();

#[derive(Deserialize)]
struct Request {
    text: String,
    #[serde(default)]
    options: CheckOptions,
    #[serde(default)]
    entries: Vec<PersonalEntry>,
}

#[derive(Serialize)]
struct Response {
    findings: Vec<Finding>,
    error: Option<String>,
}

fn check_json(input: &[u8]) -> Result<Vec<Finding>, &'static str> {
    if input.len() > MAX_REQUEST_BYTES {
        return Err("request too large");
    }
    let request: Request = serde_json::from_slice(input).map_err(|_| "invalid request")?;
    if request.text.encode_utf16().count() > MAX_TEXT_UNITS || request.entries.len() > 200 {
        return Err("request too large");
    }
    if !(1..=3).contains(&request.options.sensitivity)
        || request.entries.iter().any(|entry| {
            entry.term.trim().is_empty()
                || entry.term.encode_utf16().count() > 100
                || entry
                    .replacement
                    .as_ref()
                    .is_some_and(|text| text.encode_utf16().count() > 100)
                || (entry.kind == deai_core::PersonalKind::Replace
                    && entry
                        .replacement
                        .as_ref()
                        .is_none_or(|text| text.is_empty()))
        })
    {
        return Err("invalid options or lexicon");
    }
    let checker = CHECKER.get_or_init(Checker::new);
    let mut findings = checker.check(&request.text, &request.options);
    if request.options.personal {
        let keep = deai_core::personal_keep_ranges(&request.text, &request.entries);
        findings.retain(|f| !keep.iter().any(|&(s, e)| f.start < e && f.end > s));
        findings.extend(deai_core::check_personal(&request.text, &request.entries));
    }
    findings.sort_by_key(|f| (f.start, f.end));
    Ok(findings)
}

/// JSON/UTF-8 C ABI. The returned allocation must be freed by `deai_free_json`.
///
/// # Safety
/// `input` must point to `len` readable bytes, or be null (which returns an error).
#[no_mangle]
pub unsafe extern "C" fn deai_check_json(input: *const u8, len: usize) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if input.is_null() || len > MAX_REQUEST_BYTES {
            return Err("invalid buffer");
        }
        check_json(std::slice::from_raw_parts(input, len))
    }));
    let response = match result {
        Ok(Ok(findings)) => Response {
            findings,
            error: None,
        },
        Ok(Err(error)) => Response {
            findings: vec![],
            error: Some(error.into()),
        },
        Err(_) => Response {
            findings: vec![],
            error: Some("checker failed".into()),
        },
    };
    let json = serde_json::to_string(&response)
        .unwrap_or_else(|_| "{\"findings\":[],\"error\":\"serialization failed\"}".into());
    CString::new(json).expect("JSON escapes NUL").into_raw()
}

/// # Safety
/// `value` must be null or an unfreed pointer returned by `deai_check_json`.
#[no_mangle]
pub unsafe extern "C" fn deai_free_json(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf16_and_personal() {
        let results = check_json("{\"text\":\"😀 bad\",\"options\":{\"grammar\":false},\"entries\":[{\"kind\":\"replace\",\"term\":\"bad\",\"replacement\":\"good\",\"matchKind\":\"exact\"}]}".as_bytes()).unwrap();
        assert!(results
            .iter()
            .any(|f| f.rule_id == "personal.replace" && f.start == 3 && f.end == 6));
    }

    #[test]
    fn keep_suppression_and_toggle() {
        let request = serde_json::json!({"text":"说白了，我们需要检查。", "options":{"grammar":false}, "entries":[{"kind":"keep","term":"说白了，","replacement":null,"matchKind":"exact"}]});
        assert!(check_json(request.to_string().as_bytes())
            .unwrap()
            .is_empty());
        let request = serde_json::json!({"text":"bad", "options":{"grammar":false,"personal":false}, "entries":[{"kind":"avoid","term":"bad","replacement":null,"matchKind":"exact"}]});
        assert!(check_json(request.to_string().as_bytes())
            .unwrap()
            .is_empty());
    }

    #[test]
    fn invalid_requests_and_null_buffer() {
        assert!(check_json(b"not json").is_err());
        assert!(check_json(
            serde_json::json!({"text":"a".repeat(MAX_TEXT_UNITS + 1)})
                .to_string()
                .as_bytes()
        )
        .is_err());
        unsafe {
            let pointer = deai_check_json(std::ptr::null(), 0);
            let json = std::ffi::CStr::from_ptr(pointer).to_str().unwrap();
            assert!(json.contains("invalid buffer"));
            deai_free_json(pointer);
            deai_free_json(std::ptr::null_mut());
        }
    }
}
