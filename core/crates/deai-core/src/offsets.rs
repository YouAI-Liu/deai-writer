//! Per-check prefix tables so every offset conversion is O(1).
//! All public `Finding` offsets are UTF-16 code units (AX CFRange / JS string
//! semantics).

pub struct Utf16Map {
    /// `utf16_at_byte[i]` = UTF-16 units in `text[..i]`. Interior bytes of a
    /// multi-byte char hold the prefix of that char's first byte.
    utf16_at_byte: Vec<u32>,
    /// `utf16_at_char[i]` = UTF-16 units of the first `i` chars.
    utf16_at_char: Vec<u32>,
    /// `(utf16_offset, byte_offset)` for each char boundary, sorted.
    boundaries: Vec<(u32, usize)>,
    len: usize,
}

impl Utf16Map {
    pub fn new(text: &str) -> Self {
        let len = text.len();
        let mut utf16_at_byte = vec![0u32; len + 1];
        let mut utf16_at_char = Vec::with_capacity(text.chars().count() + 1);
        let mut boundaries = Vec::with_capacity(text.chars().count() + 1);
        utf16_at_char.push(0);
        boundaries.push((0, 0));
        let mut units = 0u32;
        for (i, c) in text.char_indices() {
            utf16_at_byte[i..i + c.len_utf8()].fill(units);
            units += c.len_utf16() as u32;
            utf16_at_char.push(units);
            boundaries.push((units, i + c.len_utf8()));
        }
        utf16_at_byte[len] = units;
        Self {
            utf16_at_byte,
            utf16_at_char,
            boundaries,
            len,
        }
    }

    pub fn byte(&self, byte_idx: usize) -> u32 {
        self.utf16_at_byte[byte_idx.min(self.len)]
    }

    pub fn char(&self, char_idx: usize) -> u32 {
        self.utf16_at_char
            .get(char_idx)
            .copied()
            .unwrap_or_else(|| *self.utf16_at_char.last().unwrap())
    }

    pub fn range_bytes(&self, start: usize, end: usize) -> (u32, u32) {
        (self.byte(start), self.byte(end))
    }

    pub fn range_chars(&self, start: usize, end: usize) -> (u32, u32) {
        (self.char(start), self.char(end))
    }

    /// Byte offset of a UTF-16 offset; snaps to the preceding char boundary.
    pub fn byte_of_utf16(&self, units: u32) -> usize {
        match self.boundaries.binary_search_by_key(&units, |(u, _)| *u) {
            Ok(i) => self.boundaries[i].1,
            Err(0) => 0,
            Err(i) => self.boundaries[i - 1].1,
        }
    }
}
