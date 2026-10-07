use std::collections::HashSet;
use std::time::Instant;

use crate::{apply_suggestion, strip_markdown, Category, CheckOptions, Checker, Finding};

fn checker() -> Checker {
    Checker::new()
}

fn opts() -> CheckOptions {
    CheckOptions::default()
}

/// All categories on, custom sensitivity.
fn opts_sens(s: u8) -> CheckOptions {
    CheckOptions {
        sensitivity: s,
        ..Default::default()
    }
}

/// Non-grammar rules only, custom sensitivity.
fn opts_no_grammar(s: u8) -> CheckOptions {
    CheckOptions {
        grammar: false,
        sensitivity: s,
        ..Default::default()
    }
}

/// JS/String.prototype.slice equivalent on UTF-16 offsets.
fn slice(text: &str, f: &Finding) -> String {
    let mut taken = 0u32;
    let mut out = String::new();
    for c in text.chars() {
        let w = c.len_utf16() as u32;
        if taken >= f.start && taken + w <= f.end {
            out.push(c);
        }
        taken += w;
    }
    out
}

fn by_id(findings: &[Finding], id: &str) -> Vec<Finding> {
    findings
        .iter()
        .filter(|f| f.rule_id == id)
        .cloned()
        .collect()
}

fn one(findings: &[Finding], id: &str) -> Finding {
    let v = by_id(findings, id);
    assert_eq!(v.len(), 1, "expected exactly one {id}, got {v:?}");
    v.into_iter().next().unwrap()
}

// =================== zh rules ===================

#[test]
fn zh_fanan() {
    let text = "我们需要的不是更多的数据，而是更好的判断力。";
    let f = one(&checker().check(text, &opts_no_grammar(3)), "zh.fanan");
    assert_eq!(slice(text, &f), "不是更多的数据，而是");
    assert_eq!(f.tier, 2);
    assert!(f.suggestions.is_empty());
}

#[test]
fn zh_fanan_variants() {
    for text in [
        "这并非技术问题，而是认知问题。",
        "关键不在于速度，而在于方向。",
        "与其说他在写代码，不如说他在写文案。",
        "这看似稳定，实则脆弱。",
        "这表面上是优化，实际上是重写。",
        "你以为用户在乎功能，其实他们只在乎能不能马上用。",
    ] {
        assert!(
            !by_id(&checker().check(text, &opts_no_grammar(3)), "zh.fanan").is_empty(),
            "zh.fanan should match: {text}"
        );
    }
}

#[test]
fn zh_fanan_negative() {
    let text = "真正的壁垒是认知。";
    assert!(by_id(&checker().check(text, &opts()), "zh.fanan").is_empty());
}

#[test]
fn zh_fanan_loose() {
    let text = "这不是终点，是起点。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.fanan_loose",
    );
    assert_eq!(slice(text, &f), "不是终点，是");
    assert_eq!(f.tier, 3);
    // tier 3 must not appear at default sensitivity
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(2)),
        "zh.fanan_loose"
    )
    .is_empty());
}

#[test]
fn zh_fanan_loose_negative() {
    // covered by zh.fanan: 而是 form only
    let text = "这不是终点，而是起点。";
    let fs = checker().check(text, &opts_no_grammar(3));
    assert!(by_id(&fs, "zh.fanan_loose").is_empty());
    assert_eq!(by_id(&fs, "zh.fanan").len(), 1);
}

#[test]
fn zh_prompt_colon() {
    let text = "一句话总结：这个方案成本太高。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.prompt_colon",
    );
    assert_eq!(slice(text, &f), "一句话总结：");
    assert_eq!(f.tier, 1);
    assert_eq!(f.suggestions, vec![String::new()]); // at sentence start
}

#[test]
fn zh_prompt_colon_mid_sentence_no_suggestion() {
    let text = "其实一句话总结：这个方案成本太高。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.prompt_colon",
    );
    assert_eq!(slice(text, &f), "一句话总结：");
    assert!(f.suggestions.is_empty()); // not at sentence start
}

#[test]
fn zh_prompt_colon_negatives() {
    // heading line skipped
    assert!(by_id(
        &checker().check("# 一句话总结：如何写好代码", &opts_no_grammar(3)),
        "zh.prompt_colon"
    )
    .is_empty());
    // colon followed by quote skipped
    assert!(by_id(
        &checker().check("他说：“明天再谈。”", &opts_no_grammar(3)),
        "zh.prompt_colon"
    )
    .is_empty());
    assert!(by_id(
        &checker().check("结论：“明天再谈。”", &opts_no_grammar(3)),
        "zh.prompt_colon"
    )
    .is_empty());
}

#[test]
fn zh_empty_list_intro() {
    let text = "我见过的几种典型场景：\n- 场景一\n- 场景二";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.empty_list_intro",
    );
    assert_eq!(slice(text, &f), "我见过的几种典型场景：");
    assert_eq!(f.tier, 1);
    assert!(f.suggestions.is_empty());
}

#[test]
fn zh_empty_list_intro_negatives() {
    // next non-empty line is not a list item
    let text = "我见过的几种典型场景：\n场景其实不多。";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.empty_list_intro"
    )
    .is_empty());
    // heading line skipped
    let text = "# 场景：\n- 场景一";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.empty_list_intro"
    )
    .is_empty());
}

#[test]
fn zh_ordinal_heading() {
    let text = "# 一、先别急着写 prompt\n# 二、把需求写成模块\n# 三、合成第一版";
    let fs = by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.ordinal_heading",
    );
    assert_eq!(fs.len(), 3);
    assert_eq!(slice(text, &fs[0]), "一、");
    assert_eq!(fs[0].tier, 1);
    assert_eq!(fs[0].suggestions, vec![String::new()]);
}

#[test]
fn zh_ordinal_heading_bold_lines() {
    let text =
        "**一、背景**\n正文一行字要足够长才行。\n**二、方案**\n更多正文在这里放着。\n**三、结论**";
    let fs = by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.ordinal_heading",
    );
    assert_eq!(fs.len(), 3);
}

#[test]
fn zh_ordinal_heading_negatives() {
    // only two ordinals
    let text = "# 一、背景\n# 二、方案";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.ordinal_heading"
    )
    .is_empty());
    // run broken by a heading without an ordinal
    let text = "# 一、背景\n# 方案\n# 二、细节\n# 三、结论";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.ordinal_heading"
    )
    .is_empty());
    // 首先/其次/最后 in body text is explicitly not a rule target
    let text = "首先清洗数据，其次训练模型，最后评估效果。";
    let fs = checker().check(text, &opts_no_grammar(3));
    assert!(by_id(&fs, "zh.ordinal_heading").is_empty());
    assert!(by_id(&fs, "zh.ordinal_heading_plain").is_empty());
}

#[test]
fn zh_ordinal_heading_plain() {
    let text = "第一、背景介绍\n第二、方案细节\n第三、最终结论";
    let fs = by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.ordinal_heading_plain",
    );
    assert_eq!(fs.len(), 3);
    assert_eq!(fs[0].tier, 2);
    assert_eq!(slice(text, &fs[0]), "第一、");
    assert_eq!(fs[0].suggestions, vec![String::new()]);
}

#[test]
fn zh_ordinal_heading_plain_negative() {
    let text = "第一、背景介绍\n第二、方案细节";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.ordinal_heading_plain"
    )
    .is_empty());
}

#[test]
fn zh_banned_opener() {
    let text = "说白了，这个项目没有足够的预算。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.banned_opener",
    );
    assert_eq!(slice(text, &f), "说白了，");
    assert_eq!(f.tier, 1);
    assert_eq!(f.suggestions, vec![String::new()]);
}

#[test]
fn zh_banned_opener_negative() {
    let text = "他把这个项目说明白了。";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.banned_opener"
    )
    .is_empty());
}

#[test]
fn zh_zero_anaphor() {
    // second paragraph opens with a review phrase, no anaphora in sentence 1
    let text = "先交代一下必要的背景信息。\n看起来像一个简单补丁，其实改动很大。";
    // note: 其实 contains 其 -> anaphor present -> NOT flagged
    let fs = checker().check(text, &opts_no_grammar(3));
    assert!(by_id(&fs, "zh.zero_anaphor").is_empty());

    let text = "先交代一下必要的背景信息。\n看起来像一个简单补丁，改动比预期大。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.zero_anaphor",
    );
    assert_eq!(slice(text, &f), "看起来");
    assert_eq!(f.tier, 1);
    assert_eq!(f.suggestions, vec!["这看起来".to_string()]);
}

#[test]
fn zh_zero_anaphor_cr_separator() {
    let text = "先交代一下必要的背景信息。\r听起来改动比预期大一些。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.zero_anaphor",
    );
    assert_eq!(slice(text, &f), "听起来");
}

#[test]
fn zh_zero_anaphor_negatives() {
    // first paragraph is exempt
    let text = "看起来像一个简单补丁，改动比预期大。";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.zero_anaphor"
    )
    .is_empty());
    // first sentence already has an anaphor (这)
    let text = "先交代一下必要的背景信息。\n值得注意的是，这配置本来就分层放着。";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.zero_anaphor"
    )
    .is_empty());
}

#[test]
fn zh_persona_metaphor() {
    let text = "它就像一位智慧的导师，默默陪你改稿。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.persona_metaphor",
    );
    assert_eq!(slice(text, &f), "像一位智慧的导师");
    assert_eq!(f.tier, 1);
    assert!(f.suggestions.is_empty());
}

#[test]
fn zh_persona_metaphor_not_only_more() {
    // second condition: 不仅…更… after the match in the same sentence
    let text = "它像一个助手，不仅能写稿，更能改稿。";
    assert_eq!(
        by_id(
            &checker().check(text, &opts_no_grammar(3)),
            "zh.persona_metaphor"
        )
        .len(),
        1
    );
}

#[test]
fn zh_persona_metaphor_negative() {
    // a concrete-person metaphor is explicitly allowed
    let text = "他像一个老师傅一样干活。";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.persona_metaphor"
    )
    .is_empty());
}

#[test]
fn zh_dash() {
    let text = "答案其实很简单——专注。";
    let f = one(&checker().check(text, &opts_no_grammar(3)), "zh.dash");
    assert_eq!(slice(text, &f), "——");
    assert_eq!(f.tier, 2);
    assert_eq!(f.suggestions, vec!["，".to_string()]);
}

#[test]
fn zh_dash_single_between_hanzi() {
    let text = "他—走了";
    let f = one(&checker().check(text, &opts_no_grammar(3)), "zh.dash");
    assert_eq!(slice(text, &f), "—");
}

#[test]
fn zh_dash_negative() {
    let text = "答案很简单，就是专注。";
    assert!(by_id(&checker().check(text, &opts_no_grammar(3)), "zh.dash").is_empty());
}

#[test]
fn zh_dunhao_list() {
    let text = "采集、存储、展示。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.dunhao_list",
    );
    assert_eq!(slice(text, &f), "采集、存储、展示");
    assert_eq!(f.tier, 2);
}

#[test]
fn zh_dunhao_list_negatives() {
    // inside a list-item line: skipped
    let text = "- 采集、存储、展示";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.dunhao_list"
    )
    .is_empty());
    // only one 顿号 in the clause
    let text = "无论是初创公司、中型企业，还是大型集团，都能用。";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.dunhao_list"
    )
    .is_empty());
}

#[test]
fn zh_nominalization() {
    let text = "团队完成了对流程的优化。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.nominalization",
    );
    assert_eq!(slice(text, &f), "完成了对流程的优化");
    assert_eq!(f.tier, 2);
}

#[test]
fn zh_nominalization_negative() {
    let text = "团队优化了流程。";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.nominalization"
    )
    .is_empty());
}

#[test]
fn zh_dang_shi() {
    let text = "当所有人都能用 AI 写文章时，内容本身就不再是优势。";
    let f = one(&checker().check(text, &opts_no_grammar(3)), "zh.dang_shi");
    assert_eq!(slice(text, &f), "当所有人都能用 AI 写文章时，");
    assert_eq!(f.tier, 2);
    assert_eq!(f.suggestions, vec!["所有人都能用 AI 写文章，".to_string()]);
}

#[test]
fn zh_dang_shi_negatives() {
    // “的时候” is normal usage
    let text = "当大家都在的时候，我们再开始。";
    assert!(by_id(&checker().check(text, &opts_no_grammar(3)), "zh.dang_shi").is_empty());
    // not at sentence start
    let text = "他说当成本下降时利润就上升。";
    assert!(by_id(&checker().check(text, &opts_no_grammar(3)), "zh.dang_shi").is_empty());
}

#[test]
fn zh_topic_shell() {
    let text = "对于早期团队来说，招人是最难的事。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.topic_shell",
    );
    assert_eq!(slice(text, &f), "对于早期团队来说");
    assert_eq!(f.tier, 2);
}

#[test]
fn zh_topic_shell_negative() {
    // mid-sentence 对于…来说 is left alone
    let text = "这件事对于团队来说很重要。";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.topic_shell"
    )
    .is_empty());
}

#[test]
fn zh_lead_connective_tiers() {
    // at paragraph start -> tier 2
    let text = "然而，这个方案并不适用。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.lead_connective",
    );
    assert_eq!(slice(text, &f), "然而，");
    assert_eq!(f.tier, 2);

    // mid-paragraph sentence start -> tier 3
    let text = "方案做完了。然而，成本还要考虑。";
    let f = one(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.lead_connective",
    );
    assert_eq!(f.tier, 3);
}

#[test]
fn zh_lead_connective_negative() {
    // mid-sentence occurrence is not flagged at all
    let text = "他很高兴，然而，他还是走了。";
    assert!(by_id(
        &checker().check(text, &opts_no_grammar(3)),
        "zh.lead_connective"
    )
    .is_empty());
}

#[test]
fn zh_this_means() {
    let text = "留存率涨到了七成。这意味着产品找到了 PMF。";
    let f = one(&checker().check(text, &opts_no_grammar(3)), "zh.this_means");
    assert_eq!(slice(text, &f), "这意味着");
    assert_eq!(f.tier, 2);
}

#[test]
fn zh_this_means_negative() {
    let text = "他说这意味着一切。";
    assert!(by_id(&checker().check(text, &opts_no_grammar(3)), "zh.this_means").is_empty());
}

#[test]
fn zh_isomorphic() {
    // three consecutive same-fingerprint sentences (>10 UTF-16 units, 1 comma each)
    let text = "他打开了电脑，开始写代码。她打开了窗户，开始看风景。我打开了书本，开始读文章。";
    let f = one(&checker().check(text, &opts_no_grammar(3)), "zh.isomorphic");
    assert_eq!(slice(text, &f), text);
    assert_eq!(f.tier, 2);
}

#[test]
fn zh_isomorphic_negatives() {
    // only two matching sentences -> tier 3 (invisible at default sensitivity)
    let text = "他打开了电脑，开始写代码。她打开了窗户，开始看风景。结论完全不同了，这句话结构不一样，长度也超出不少去了。";
    let fs = checker().check(text, &opts_no_grammar(2));
    assert!(by_id(&fs, "zh.isomorphic").is_empty());
    let fs = checker().check(text, &opts_no_grammar(3));
    let f = one(&fs, "zh.isomorphic");
    assert_eq!(f.tier, 3);
}

#[test]
fn zh_long_attr() {
    let text = "这是一个能够让团队在不增加人力的情况下显著提升审核速度的工具。";
    let f = one(&checker().check(text, &opts_no_grammar(3)), "zh.long_attr");
    assert_eq!(
        slice(text, &f),
        "一个能够让团队在不增加人力的情况下显著提升审核速度的工具"
    );
    assert_eq!(f.tier, 3);
}

#[test]
fn zh_long_attr_chain() {
    let text = "我们讨论了他的方案的优点的局限性的问题。";
    assert_eq!(
        by_id(&checker().check(text, &opts_no_grammar(3)), "zh.long_attr").len(),
        1
    );
}

#[test]
fn zh_long_attr_negative() {
    let text = "这是一个很好用的工具。";
    assert!(by_id(&checker().check(text, &opts_no_grammar(3)), "zh.long_attr").is_empty());
}

// =================== en rules ===================

fn en(text: &str) -> Vec<Finding> {
    // zh/md off to keep assertions tight
    checker().check(
        text,
        &CheckOptions {
            grammar: false,
            ai_tone_zh: false,
            markdown: false,
            sensitivity: 3,
            ..Default::default()
        },
    )
}

#[test]
fn en_chat_leftover() {
    let text = "Here is the fix. I hope this helps.";
    let fs = en(text);
    let f = one(&fs, "en.chat_leftover");
    assert_eq!(slice(text, &f), "I hope this helps.");
    assert_eq!(f.tier, 1);
    assert_eq!(f.suggestions, vec![String::new()]);
}

#[test]
fn en_chat_leftover_negative() {
    let text = "I hope this code compiles.";
    assert!(by_id(&en(text), "en.chat_leftover").is_empty());
}

#[test]
fn en_filler_opener() {
    let text = "It's worth noting that the API is slow.";
    let f = one(&en(text), "en.filler_opener");
    assert_eq!(slice(text, &f), "It's worth noting that t");
    assert_eq!(f.tier, 1);
    assert_eq!(f.suggestions, vec!["T".to_string()]);
    // applying the suggestion produces the cleaned sentence
    assert_eq!(
        apply_suggestion(text, f.start, f.end, "T"),
        "The API is slow."
    );
}

#[test]
fn en_filler_opener_negative() {
    let text = "He said it's worth noting that the API is slow.";
    assert!(by_id(&en(text), "en.filler_opener").is_empty());
}

#[test]
fn en_stock_phrase() {
    let text = "We delve into the details.";
    let f = one(&en(text), "en.stock_phrase");
    assert_eq!(slice(text, &f), "delve into");
    assert_eq!(f.tier, 1);
    assert!(f.suggestions.is_empty());
}

#[test]
fn en_stock_phrase_negative() {
    let text = "We discuss the details.";
    assert!(by_id(&en(text), "en.stock_phrase").is_empty());
}

#[test]
fn en_inflated() {
    let text = "This marks a pivotal moment for the team.";
    let f = one(&en(text), "en.inflated");
    assert_eq!(slice(text, &f), "marks a pivotal moment");
    assert_eq!(f.tier, 2);
}

#[test]
fn en_inflated_negative() {
    let text = "This is a big moment for the team.";
    assert!(by_id(&en(text), "en.inflated").is_empty());
}

#[test]
fn en_vague_attribution() {
    let text = "Experts say the trend will continue.";
    let f = one(&en(text), "en.vague_attribution");
    assert_eq!(slice(text, &f), "Experts say");
    assert_eq!(f.tier, 2);
}

#[test]
fn en_vague_attribution_negative() {
    let text = "Alice says the trend will continue.";
    assert!(by_id(&en(text), "en.vague_attribution").is_empty());
}

#[test]
fn en_not_but() {
    let text = "It's not just about speed, but reliability.";
    let f = one(&en(text), "en.not_but");
    assert_eq!(slice(text, &f), "It's not just about speed, but");
    assert_eq!(f.tier, 2);
}

#[test]
fn en_not_but_negative() {
    let text = "It is about speed.";
    assert!(by_id(&en(text), "en.not_but").is_empty());
}

#[test]
fn en_not_only() {
    let text = "This not only saves time but also reduces cost.";
    let f = one(&en(text), "en.not_only");
    assert_eq!(slice(text, &f), "not only saves time but also ");
    assert_eq!(f.tier, 3);
}

#[test]
fn en_not_only_negative() {
    let text = "He is not only a developer.";
    assert!(by_id(&en(text), "en.not_only").is_empty());
}

#[test]
fn en_em_dash() {
    let text = "It works — surprisingly well.";
    let f = one(&en(text), "en.em_dash");
    assert_eq!(slice(text, &f), " — ");
    assert_eq!(f.tier, 2);
    assert_eq!(f.suggestions, vec![", ".to_string()]);

    let text = "The answer — focus.";
    assert_eq!(by_id(&en(text), "en.em_dash").len(), 1);
}

#[test]
fn en_em_dash_ascii() {
    let text = "It works -- surprisingly well.";
    let f = one(&en(text), "en.em_dash");
    assert_eq!(slice(text, &f), " -- ");
}

#[test]
fn en_em_dash_negative() {
    let text = "It works surprisingly-well.";
    assert!(by_id(&en(text), "en.em_dash").is_empty());
}

#[test]
fn en_em_dash_chinese_negatives() {
    // —— is zh.dash territory: no en.em_dash at all
    let text = "答案其实很简单——专注。";
    let fs = checker().check(text, &opts_no_grammar(3));
    assert!(by_id(&fs, "en.em_dash").is_empty());
    assert_eq!(by_id(&fs, "zh.dash").len(), 1);
    // single — between hanzi is covered by zh.dash, not en.em_dash
    let text = "他说—好";
    let fs = checker().check(text, &opts_no_grammar(3));
    assert!(by_id(&fs, "en.em_dash").is_empty());
    assert_eq!(by_id(&fs, "zh.dash").len(), 1);
    // fullwidth-neighbour — is also left to zh rules
    let text = "a —，b";
    assert!(by_id(&en(text), "en.em_dash").is_empty());
}

#[test]
fn en_signpost() {
    // two signposts in one paragraph -> tier 2 each
    let text = "Moreover, it failed! Furthermore, it burned.";
    let fs = by_id(&en(text), "en.signpost");
    assert_eq!(fs.len(), 2);
    assert_eq!(fs[0].tier, 2);
    assert_eq!(slice(text, &fs[0]), "Moreover,");
}

#[test]
fn en_signpost_negative() {
    // a lone signpost is tier 3 -> invisible at default sensitivity
    let text = "Moreover, it failed.";
    let fs = checker().check(
        text,
        &CheckOptions {
            grammar: false,
            ai_tone_zh: false,
            markdown: false,
            sensitivity: 2,
            ..Default::default()
        },
    );
    assert!(by_id(&fs, "en.signpost").is_empty());
    let f = one(&en(text), "en.signpost");
    assert_eq!(f.tier, 3);
}

#[test]
fn en_ai_vocab() {
    let text = "The intricate and multifaceted realm.";
    let fs = by_id(&en(text), "en.ai_vocab");
    assert_eq!(fs.len(), 3);
    assert_eq!(fs[0].tier, 2);
    assert_eq!(slice(text, &fs[0]), "intricate");
}

#[test]
fn en_ai_vocab_negative() {
    // one word alone is tier 3
    let text = "The realm is vast.";
    let fs = by_id(&en(text), "en.ai_vocab");
    assert_eq!(fs.len(), 1);
    assert_eq!(fs[0].tier, 3);
}

// =================== markdown rules ===================

fn md(text: &str) -> Vec<Finding> {
    checker().check(
        text,
        &CheckOptions {
            grammar: false,
            ai_tone_en: false,
            ai_tone_zh: false,
            sensitivity: 3,
            ..Default::default()
        },
    )
}

#[test]
fn md_bold() {
    let text = "这是**粗体**文字";
    let f = one(&md(text), "md.bold");
    assert_eq!(slice(text, &f), "**粗体**");
    assert_eq!(f.tier, 1);
    assert_eq!(f.suggestions, vec!["粗体".to_string()]);
}

#[test]
fn md_bold_underscore() {
    let text = "a __b__ c";
    let f = one(&md(text), "md.bold");
    assert_eq!(slice(text, &f), "__b__");
    assert_eq!(f.suggestions, vec!["b".to_string()]);
}

#[test]
fn md_strike() {
    let text = "这是~~旧~~方案";
    let f = one(&md(text), "md.strike");
    assert_eq!(slice(text, &f), "~~旧~~");
    assert_eq!(f.suggestions, vec!["旧".to_string()]);
}

#[test]
fn md_strike_negative() {
    assert!(by_id(&md("这是旧方案"), "md.strike").is_empty());
}

#[test]
fn md_heading() {
    let text = "# 标题\n正文内容在这里";
    let f = one(&md(text), "md.heading");
    assert_eq!(slice(text, &f), "# ");
    assert_eq!(f.suggestions, vec![String::new()]);
}

#[test]
fn md_heading_negative() {
    assert!(by_id(&md("#hashtag content"), "md.heading").is_empty());
}

#[test]
fn md_blockquote() {
    let text = "> 引用的一句话";
    let f = one(&md(text), "md.blockquote");
    assert_eq!(slice(text, &f), "> ");
    assert_eq!(f.suggestions, vec![String::new()]);
}

#[test]
fn md_blockquote_negative() {
    assert!(by_id(&md("a > b 比较"), "md.blockquote").is_empty());
}

#[test]
fn md_inline_code() {
    let text = "调用 `build()` 方法";
    let f = one(&md(text), "md.inline_code");
    assert_eq!(slice(text, &f), "`build()`");
    assert_eq!(f.suggestions, vec!["build()".to_string()]);
}

#[test]
fn md_inline_code_negative() {
    assert!(by_id(&md("调用 build 方法"), "md.inline_code").is_empty());
}

#[test]
fn md_code_fence() {
    let text = "```rust\nlet x = 1;\n```\n";
    let fs = by_id(&md(text), "md.code_fence");
    assert_eq!(fs.len(), 2);
    assert_eq!(slice(text, &fs[0]), "```rust\n");
    assert_eq!(fs[0].suggestions, vec![String::new()]);
    // content inside the fence produces no markdown findings
    assert_eq!(md(text).len(), 2);
}

#[test]
fn md_hr() {
    let text = "上文\n---\n下文";
    let f = one(&md(text), "md.hr");
    assert_eq!(slice(text, &f), "---");
    assert!(by_id(&md(text), "md.list_bullet").is_empty());
}

#[test]
fn md_hr_negative() {
    assert!(by_id(&md("-- just two"), "md.hr").is_empty());
}

#[test]
fn md_link() {
    let text = "看[这里](https://a.com)吧";
    let f = one(&md(text), "md.link");
    assert_eq!(slice(text, &f), "[这里](https://a.com)");
    assert_eq!(
        f.suggestions,
        vec![
            "这里".to_string(),
            "这里 (https://a.com)".to_string(),
            "https://a.com".to_string()
        ]
    );
}

#[test]
fn md_link_negative_image() {
    let text = "![截图](a.png)";
    assert!(by_id(&md(text), "md.link").is_empty());
    let f = one(&md(text), "md.image");
    assert_eq!(slice(text, &f), "![截图](a.png)");
    assert_eq!(f.suggestions, vec!["截图".to_string()]);
}

#[test]
fn md_image_empty_alt() {
    let text = "![](a.png)";
    let f = one(&md(text), "md.image");
    assert_eq!(f.suggestions, vec![String::new()]);
}

#[test]
fn md_list_bullet() {
    let text = "- 第一项内容";
    let f = one(&md(text), "md.list_bullet");
    assert_eq!(slice(text, &f), "- ");
    assert_eq!(f.tier, 2);
    assert_eq!(f.suggestions, vec![String::new()]);
}

#[test]
fn md_list_bullet_negative() {
    assert!(by_id(&md("a-b"), "md.list_bullet").is_empty());
}

#[test]
fn md_italic() {
    let text = "这是 *强调* 文字";
    let f = one(&md(text), "md.italic");
    assert_eq!(slice(text, &f), "*强调*");
    assert_eq!(f.tier, 2);
    assert_eq!(f.suggestions, vec!["强调".to_string()]);
}

#[test]
fn md_italic_negatives() {
    // math-ish: neighbours are alphanumeric
    assert!(by_id(&md("a*b*c"), "md.italic").is_empty());
    // snake_case untouched (single underscores aren't `__`)
    assert!(by_id(&md("snake_case_name"), "md.bold").is_empty());
    assert!(by_id(&md("snake_case_name"), "md.italic").is_empty());
    // inner whitespace rejected
    assert!(by_id(&md("a *b *c"), "md.italic").is_empty());
    // bold is not italic
    let fs = md("这是**粗体**文字");
    assert!(by_id(&fs, "md.italic").is_empty());
}

#[test]
fn md_table_row() {
    let text = "| 名称 | 数值 |";
    let f = one(&md(text), "md.table_row");
    assert_eq!(slice(text, &f), "| 名称 | 数值 |");
    assert_eq!(f.tier, 2);
    assert!(f.suggestions.is_empty());
}

#[test]
fn md_table_row_negative() {
    assert!(by_id(&md("| 只有一侧"), "md.table_row").is_empty());
}

#[test]
fn md_escape() {
    let text = "这里的 \\* 不是斜体";
    let f = one(&md(text), "md.escape");
    assert_eq!(slice(text, &f), "\\*");
    assert_eq!(f.suggestions, vec!["*".to_string()]);
}

#[test]
fn md_escape_negative() {
    assert!(by_id(&md("正常文本"), "md.escape").is_empty());
}

// =================== exclusion zones ===================

#[test]
fn exclusion_quotes_zh() {
    // “不是…而是” inside quotes must not be flagged by zh rules
    for text in [
        "他说：“这不是工具，而是伙伴。”",
        "他说：「这不是工具，而是伙伴。」",
        "他说：『这不是工具，而是伙伴。』",
        "He said: \"这不是工具，而是伙伴。\"",
    ] {
        let fs = checker().check(text, &opts_no_grammar(3));
        assert!(
            fs.iter().all(|f| f.category != Category::AiToneZh),
            "zh findings leaked inside quotes: {text} -> {fs:?}"
        );
    }
}

#[test]
fn exclusion_fenced_code() {
    let text = "前文。\n```\n这不是工具，而是别的。We delve into it. **bold**\n```\n后文。";
    let fs = checker().check(text, &opts_no_grammar(3));
    assert!(by_id(&fs, "zh.fanan").is_empty());
    assert!(by_id(&fs, "en.stock_phrase").is_empty());
    // markdown rules still see only the fence lines
    let mds: Vec<_> = fs
        .iter()
        .filter(|f| f.category == Category::Markdown)
        .collect();
    assert_eq!(mds.len(), 2);
    assert!(mds.iter().all(|f| f.rule_id == "md.code_fence"));
}

#[test]
fn exclusion_inline_code() {
    let text = "使用 `delve into` 这个词。";
    let fs = checker().check(text, &opts_no_grammar(3));
    assert!(by_id(&fs, "en.stock_phrase").is_empty());
    // but the inline code itself is a markdown finding
    assert_eq!(by_id(&fs, "md.inline_code").len(), 1);
}

// =================== dedupe / sensitivity ===================

#[test]
fn dedupe_prompt_colon_beats_this_means() {
    let text = "换句话说：结果一致。";
    let fs = checker().check(text, &opts_no_grammar(3));
    let zh: Vec<_> = fs
        .iter()
        .filter(|f| f.category == Category::AiToneZh)
        .collect();
    assert_eq!(zh.len(), 1);
    assert_eq!(zh[0].rule_id, "zh.prompt_colon");
}

#[test]
fn dedupe_banned_opener_beats_zero_anaphor() {
    // non-first paragraph starting with 说白了， hits banned_opener
    // ("说白了，") and zero_anaphor ("说白了"); the supersede pair drops
    // zero_anaphor on overlap
    let text = "先交代一下必要的背景信息。\n说白了，预算仍然不够。";
    let fs = checker().check(text, &opts_no_grammar(3));
    let zh: Vec<_> = fs
        .iter()
        .filter(|f| f.category == Category::AiToneZh)
        .collect();
    assert_eq!(zh.len(), 1);
    assert_eq!(zh[0].rule_id, "zh.banned_opener");
}

#[test]
fn dedupe_overlapping_findings_coexist() {
    // dunhao_list and nominalization overlap but neither supersedes the other
    let text = "我们需要从采集、存储、展示三个方面进行全面的优化。";
    let fs = checker().check(text, &opts_no_grammar(3));
    assert_eq!(by_id(&fs, "zh.dunhao_list").len(), 1);
    assert_eq!(by_id(&fs, "zh.nominalization").len(), 1);
}

#[test]
fn dedupe_markdown_nested_markup() {
    // nested markup reports both findings (md has no generic overlap dedupe)
    let text = "**[文档](https://a.com)**";
    let fs = md(text);
    assert_eq!(by_id(&fs, "md.bold").len(), 1);
    assert_eq!(by_id(&fs, "md.link").len(), 1);
}

#[test]
fn sensitivity_filters_by_tier() {
    // banned_opener t1 + dash t2 + fanan_loose t3 (grammar/en off)
    let text = "说穿了，没别的办法。他——走了。这不是终点，是起点。";
    let mk = |s: u8| -> HashSet<String> {
        checker()
            .check(
                text,
                &CheckOptions {
                    grammar: false,
                    ai_tone_en: false,
                    markdown: false,
                    sensitivity: s,
                    ..Default::default()
                },
            )
            .iter()
            .map(|f| f.rule_id.clone())
            .collect()
    };
    assert_eq!(mk(1), HashSet::from(["zh.banned_opener".to_string()]));
    assert_eq!(
        mk(2),
        HashSet::from(["zh.banned_opener".to_string(), "zh.dash".to_string()])
    );
    assert_eq!(
        mk(3),
        HashSet::from([
            "zh.banned_opener".to_string(),
            "zh.dash".to_string(),
            "zh.fanan_loose".to_string()
        ])
    );
}

// =================== shared APIs ===================

#[test]
fn strip_markdown_sample() {
    let text = "# 标题\n这是**粗体**和 `代码`，还有[链接](https://a.com)。\n\n- 项目一\n- 项目二\n\n---\n\n```rust\nlet x = 1;\n```\n";
    let stripped = strip_markdown(text, &CheckOptions::default());
    assert_eq!(
        stripped,
        "标题\n这是粗体和 代码，还有链接。\n\n项目一\n项目二\n\n\n\nlet x = 1;\n"
    );
}

#[test]
fn strip_markdown_nested_passes() {
    // bold wrapping a link needs two passes
    assert_eq!(
        strip_markdown("**[文档](https://a.com)**", &CheckOptions::default()),
        "文档"
    );
    // blockquote wrapping a heading needs two passes
    assert_eq!(
        strip_markdown("> ## 标题", &CheckOptions::default()),
        "标题"
    );
    // no applicable findings -> unchanged
    assert_eq!(
        strip_markdown("纯文本。", &CheckOptions::default()),
        "纯文本。"
    );
}

#[test]
fn apply_suggestion_basic() {
    // UTF-16 offsets; emoji counts as two units
    let text = "😀 这是**粗体**文字";
    let fs = md(text);
    let f = one(&fs, "md.bold");
    assert_eq!(slice(text, &f), "**粗体**");
    assert_eq!(
        apply_suggestion(text, f.start, f.end, "粗体"),
        "😀 这是粗体文字"
    );
}

#[test]
fn harper_still_works_and_tier1() {
    let text = "This is an test.";
    let fs = checker().check(text, &CheckOptions::default());
    let f = fs.iter().find(|f| f.category == Category::Grammar).unwrap();
    assert_eq!(slice(text, &f), "an");
    assert_eq!(f.tier, 1);
    assert!(f.suggestions.iter().any(|s| s == "a"));
}

#[test]
fn mixed_emoji_cjk_offsets() {
    let text = "😀 我们不是工具，而是伙伴。This is an test.";
    let fs = checker().check(text, &CheckOptions::default());
    for f in &fs {
        // every finding's slice is non-empty and the offsets are in bounds
        assert!(f.start < f.end);
    }
    let zh = one(&fs, "zh.fanan");
    assert_eq!(slice(text, &zh), "不是工具，而是");
    let grammar = fs.iter().find(|f| f.category == Category::Grammar).unwrap();
    assert_eq!(slice(text, &grammar), "an");
}

#[test]
fn findings_sorted_by_start() {
    let text = "说白了，这不是终点，是起点。This is an test. **加粗**";
    let fs = checker().check(text, &opts_sens(3));
    let starts: Vec<u32> = fs.iter().map(|f| f.start).collect();
    let mut sorted = starts.clone();
    sorted.sort();
    assert_eq!(starts, sorted);
}

// =================== perf ===================

#[test]
#[ignore]
fn perf_20k_utf16() {
    let unit = "这是一个用于测试的混合段落，包含顿号、举例，也带 delve into 和 Moreover, 这类词。**加粗**、`代码`、[链接](https://a.com) 都出现。当成本趋近于零时，方向更重要。\n";
    // ~90 UTF-16 units per line; repeat to reach ~20k
    let reps = 20000 / (unit.chars().map(|c| c.len_utf16() as u32).sum::<u32>() as usize) + 1;
    let text = unit.repeat(reps);
    let total_utf16: u32 = text.chars().map(|c| c.len_utf16() as u32).sum();
    println!("total UTF-16 units: {total_utf16}");

    let checker = Checker::new();
    let no_grammar = CheckOptions {
        grammar: false,
        sensitivity: 3,
        ..Default::default()
    };
    let t0 = Instant::now();
    let fs = checker.check(&text, &no_grammar);
    let non_grammar_ms = t0.elapsed().as_secs_f64() * 1000.0;
    println!(
        "non-grammar check: {non_grammar_ms:.2} ms ({} findings)",
        fs.len()
    );

    let t0 = Instant::now();
    let fs = checker.check(
        &text,
        &CheckOptions {
            sensitivity: 3,
            ..Default::default()
        },
    );
    let full_ms = t0.elapsed().as_secs_f64() * 1000.0;
    println!(
        "full check incl. harper: {full_ms:.2} ms ({} findings)",
        fs.len()
    );

    // per-rule breakdown for tuning
    let t = Instant::now();
    let map = crate::offsets::Utf16Map::new(&text);
    println!(
        "  Utf16Map::new: {:.2} ms",
        t.elapsed().as_secs_f64() * 1000.0
    );
    let t = Instant::now();
    let lines = crate::text::lines(&text);
    println!("  lines(): {:.2} ms", t.elapsed().as_secs_f64() * 1000.0);
    let t = Instant::now();
    let exclusions = crate::text::Exclusions::build(&text, &lines);
    println!(
        "  Exclusions::build: {:.2} ms",
        t.elapsed().as_secs_f64() * 1000.0
    );
    let ctx = crate::rules::Ctx {
        text: &text,
        map: &map,
        lines: &lines,
        exclusions: &exclusions,
    };
    let mut times: Vec<(String, f64)> = Vec::new();
    for rule in crate::rules::all() {
        let t = Instant::now();
        let fs = rule.check(&ctx);
        let id = fs
            .first()
            .map(|f| f.rule_id.clone())
            .unwrap_or_else(|| "?".into());
        times.push((id, t.elapsed().as_secs_f64() * 1000.0));
    }
    times.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
    let sum: f64 = times.iter().map(|t| t.1).sum();
    println!("  rule sum: {sum:.2} ms ({} rules)", times.len());
    // pipeline overhead: collect + per-category dedupe + sort
    let t = Instant::now();
    let mut per_cat: [Vec<(usize, Finding)>; 4] = Default::default();
    for (i, rule) in crate::rules::all().iter().enumerate() {
        let idx = match rule.category() {
            Category::Grammar => 0,
            Category::AiToneEn => 1,
            Category::AiToneZh => 2,
            Category::Markdown => 3,
        };
        for f in rule.check(&ctx) {
            per_cat[idx].push((i, f));
        }
    }
    println!(
        "  re-run rules+collect: {:.2} ms ({} raw)",
        t.elapsed().as_secs_f64() * 1000.0,
        per_cat.iter().map(Vec::len).sum::<usize>()
    );
    let t = Instant::now();
    let mut deduped: Vec<Finding> = per_cat.into_iter().flat_map(crate::dedupe).collect();
    println!(
        "  dedupe: {:.2} ms -> {}",
        t.elapsed().as_secs_f64() * 1000.0,
        deduped.len()
    );
    let t = Instant::now();
    deduped.sort_by_key(|f| (f.start, f.end));
    println!("  sort: {:.2} ms", t.elapsed().as_secs_f64() * 1000.0);
    for (id, ms) in times.iter().take(10) {
        println!("  {id}: {ms:.2} ms");
    }

    assert!(
        non_grammar_ms < 10.0,
        "non-grammar check too slow: {non_grammar_ms} ms"
    );
}
