//! All finding offsets are UTF-16 code units (matching macOS AX CFRange and JS
//! strings). These helpers convert from Rust char/byte indices into that unit.

/// UTF-16 length of a string slice.
pub fn utf16_len(s: &str) -> u32 {
    s.chars().map(|c| c.len_utf16() as u32).sum()
}

/// UTF-16 offset of a char index (as produced by `str::chars().enumerate()` or
/// harper spans).
pub fn char_to_utf16(text: &str, char_idx: usize) -> u32 {
    text.chars()
        .take(char_idx)
        .map(|c| c.len_utf16() as u32)
        .sum()
}

/// UTF-16 offset of a byte index (as produced by regex matches).
pub fn byte_to_utf16(text: &str, byte_idx: usize) -> u32 {
    utf16_len(&text[..byte_idx])
}

/// UTF-16 `(start, end)` for a char-index range.
pub fn char_range_to_utf16(text: &str, start: usize, end: usize) -> (u32, u32) {
    (char_to_utf16(text, start), char_to_utf16(text, end))
}

/// UTF-16 `(start, end)` for a byte-index range.
pub fn byte_range_to_utf16(text: &str, start: usize, end: usize) -> (u32, u32) {
    (byte_to_utf16(text, start), byte_to_utf16(text, end))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// UTF-16 slice helper for tests: equivalent of JS `String.prototype.slice`.
    fn utf16_slice(text: &str, start: u32, end: u32) -> String {
        let mut taken = 0u32;
        let mut out = String::new();
        for c in text.chars() {
            let w = c.len_utf16() as u32;
            if taken >= start && taken + w <= end {
                out.push(c);
            }
            taken += w;
        }
        out
    }

    #[test]
    fn ascii_offsets() {
        assert_eq!(char_to_utf16("hello", 3), 3);
        assert_eq!(byte_to_utf16("hello", 3), 3);
    }

    #[test]
    fn chinese_offsets() {
        let text = "这是**粗体**文字";
        // every CJK char is one UTF-16 code unit, like ASCII
        assert_eq!(byte_to_utf16(text, "这是**".len()), 4);
        assert_eq!(byte_to_utf16(text, text.len()), 10);
        let (s, e) = char_range_to_utf16(text, 2, 8);
        assert_eq!((s, e), (2, 8));
        assert_eq!(utf16_slice(text, s, e), "**粗体**");
    }

    #[test]
    fn emoji_counts_as_two() {
        let text = "😀 This is an test";
        // 😀 is a surrogate pair: 2 UTF-16 code units, 1 char, 4 bytes
        assert_eq!(char_to_utf16(text, 1), 2);
        assert_eq!(byte_to_utf16(text, "😀".len()), 2);
        // "an" is char index 11..12 but UTF-16 offset 12..13
        assert_eq!(char_range_to_utf16(text, 11, 12), (12, 13));
        assert_eq!(utf16_slice(text, 12, 13), "n");
        assert_eq!(utf16_slice(text, 11, 13), "an");
        assert_eq!(utf16_slice(text, 0, 2), "😀");
    }
}
