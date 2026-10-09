# 演示语料 / Demo corpus

这些模拟文稿用于演示 AI 语气、英文语法和 Markdown 清理。复制各场景下的正文，不含场景说明；触发条件见 [规则规格](../../core/crates/deai-core/RULES.md)。年份范围和缩写保留在正文中，便于同时观察误报保护。

## 1. Word · 学术论文摘要（中文）

> 场景：在 Word 里写胶质瘤导航摘要，展示中文下划线、卡片替换和选中改写。正文共两段。

本研究回顾了 2019—2023 年 312 例脑胶质瘤患者的手术记录，比较术前 MRI 与术中导航坐标。研究团队完成了对定位误差的分析，并记录配准时间、切除范围、术后功能评分。导航的主要价值不是增加影像数量，而是帮助术者核对病灶边界。

值得注意的是，定位误差随脑组织位移增大。对于术中导航来说，导航精度取决于影像更新频率。当术者完成影像更新时，导航坐标与病灶边界重新对齐。核心是：更新影像后再核对坐标——减少位移造成的偏差。这意味着，影像更新可减少定位偏差。

## 2. 备忘录 · 商业周报（中文）

> 场景：在备忘录里写周报，展示选中检查快捷键（默认 ⌃⌥R）、卡片逐条处理和个人词库。
> 个人词库演示：预先添加词条「替换：获客成本 → 客户获取成本」「保留：华东区」。默认检测无需添加词条。

本周 OKR 的重点是降低获客成本。

说白了，团队完成了对投放流程的优化，检查了素材、落地页、转化路径。增长不是简单地增加预算，而是把预算投向已经验证的渠道。关键是：先修复支付失败——减少已经进入结算页的客户流失。

看起来投放效率已经改善，华东区转化率环比提升了 18%。关于渠道预算，我们将保留转化稳定的两组广告。当团队完成支付排查时，客户可以正常提交订单。这意味着，支付失败造成的订单流失减少。

## 3. 文本编辑 · 英文商务邮件草稿（TextEdit）

> 场景：在文本编辑里写英文邮件草稿，展示英文语法和 AI 语气，再切到英文界面演示改写。

Hi Sarah,

It's worth noting that the Q3 campaign reduced churn by 12%. I wanted to delve into the results, which played a pivotal role in our planning. Their is a few points to review before we set the next OKR. It's not just a number — it's a testament to the work on customer onboarding.

Moreover, the support team can review the draft on Friday. Furthermore, we can agree on the Q4 budget next week. Let me know if you have any questions!

Best,
Alex

## 4. Markdown 残留 · 从 AI 对话里复制出来的文字（TextEdit / Word）

> 场景：把 AI 对话中的回答粘贴进文档，展示 Markdown 标记检测和整篇清理。

## 项目进展总结

**核心结论**：本季度用户留存率提升至 **63%**，团队完成了对引导流程的优化。关键是：让新客户在首次登录后完成设置。

OKR 看板已更新。

本周的基础检查包括：

- 核对新用户引导流程
- 更新[客户反馈](https://example.com/feedback)记录
- 检查 `status` 字段中的待办任务

> 下一步，客服团队将复核支付失败的订单。

## 5. 英文学术段落（Word）

> 场景：在 Word 中检查英文学术段落，保留 MRI 等专业缩写。

This study delves into the role of MRI in planning brain tumor surgery. We used an navigation system to compare the images. Our findings show that navigation reduced the mean registration error from 4 mm to 2 mm. It is worth noting that the updated images helped surgeons check the tumor boundary — a step that plays a crucial role in navigation. Moreover, the results highlight the importance of repeated registration. Furthermore, studies suggest that navigation supports accurate localization, paving the way for a larger trial.
