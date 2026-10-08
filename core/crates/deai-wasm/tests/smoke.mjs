// Run: wasm-pack build --target nodejs (from core/crates/deai-wasm), then
//      node tests/smoke.mjs
import { strict as assert } from 'node:assert';
import pkg from '../pkg/deai_wasm.js';

const { Checker, strip_markdown, apply_suggestion, check_personal, personal_keep_ranges } = pkg;
const checker = new Checker();

const text = '我们不是工具，而是伙伴。This is an test.';
const opts = { grammar: true, ai_tone_en: true, ai_tone_zh: true, markdown: true };
const findings = checker.check(text, opts);

assert.ok(Array.isArray(findings), 'check returns an array');
assert.ok(findings.length >= 2, `expected >=2 findings, got ${findings.length}`);

const zh = findings.find(f => f.category === 'AiToneZh');
assert.ok(zh, 'expected an AiToneZh finding');
assert.equal(zh.rule_id, 'zh.fanan');
// Offsets are UTF-16 code units, so JS slice must reproduce the matched text.
assert.equal(text.slice(zh.start, zh.end), '不是工具，而是');
assert.equal(zh.tier, 2);

// Every finding carries a tier in 1..=3.
assert.ok(
  findings.every(f => Number.isInteger(f.tier) && f.tier >= 1 && f.tier <= 3),
  'every finding must have tier 1..3'
);

const grammar = findings.find(f => f.category === 'Grammar');
assert.ok(grammar, 'expected a Grammar finding');
assert.equal(text.slice(grammar.start, grammar.end), 'an');
assert.equal(grammar.tier, 1);
assert.ok(grammar.suggestions.includes('a'), 'grammar suggestion should include "a"');

// Findings sorted by start.
const starts = findings.map(f => f.start);
assert.deepEqual(starts, [...starts].sort((a, b) => a - b));

// Sensitivity filters by tier: zh.fanan_loose is tier 3.
const zhOnly = s => ({
  grammar: false,
  ai_tone_en: false,
  ai_tone_zh: true,
  markdown: false,
  sensitivity: s,
});
const looseText = '这不是终点，是起点。';
assert.equal(
  checker.check(looseText, zhOnly(2)).filter(f => f.rule_id === 'zh.fanan_loose').length,
  0,
  'tier-3 finding must be hidden at sensitivity 2'
);
assert.equal(
  checker.check(looseText, zhOnly(3)).filter(f => f.rule_id === 'zh.fanan_loose').length,
  1,
  'tier-3 finding must appear at sensitivity 3'
);

// strip_markdown: heading, bold, inline code removed.
assert.equal(
  strip_markdown('# 标题\n这是**粗体**和 `代码`。', {}),
  '标题\n这是粗体和 代码。',
  'strip_markdown result'
);

// apply_suggestion uses UTF-16 offsets.
assert.equal(apply_suggestion('这是**粗体**文字', 2, 8, '粗体'), '这是粗体文字');

// Emoji surrogate pair shifts harper's char-based spans by one UTF-16 unit.
const emojiText = '😀 This is an test';
const eFindings = checker.check(emojiText, opts);
const eGrammar = eFindings.find(f => f.category === 'Grammar');
assert.ok(eGrammar, 'expected a Grammar finding after emoji');
assert.equal(emojiText.slice(eGrammar.start, eGrammar.end), 'an');

// check_personal: replace/avoid findings at UTF-16 offsets; keep → no finding
const pText = '说白了，赋能 ACME 保留词';
const pEntries = [
  { kind: 'replace', term: '赋能', replacement: '帮助', matchKind: 'exact' },
  { kind: 'avoid', term: '说白了', matchKind: 'exact' },
  { kind: 'keep', term: '保留词', matchKind: 'exact' },
];
const pf = check_personal(pText, pEntries);
assert.equal(pf.length, 2, `expected 2 personal findings, got ${pf.length}`);
assert.equal(pf[0].category, 'Personal');
assert.equal(pf[0].rule_id, 'personal.avoid');
assert.equal(pText.slice(pf[1].start, pf[1].end), '赋能');
assert.equal(pf[1].suggestions[0], '帮助');
// 保留词 sits at UTF-16 units 12..15 in pText
assert.deepEqual(personal_keep_ranges(pText, pEntries), [[12, 15]]);

console.log('smoke ok:', JSON.stringify(findings, null, 2));
