# 演示与介绍用语 / Demo copy notes

产品介绍以 [中文 README](../../README.zh-CN.md) 和 [English README](../../README.md) 为准。本文件记录演示文案的能力边界，避免后续制作时沿用过时描述。

The [English README](../../README.md) and [Chinese README](../../README.zh-CN.md) describe the current app. Keep future demo copy within these limits:

- 已验证的演示范围是 Word、文本编辑和备忘录。浏览器默认关闭，仍不支持完整检查流程。 / The demonstrated apps are Word, TextEdit and Notes. Browsers are disabled by default and do not support the full checking flow.
- 下划线来自本地规则；命中不代表文字由 AI 生成。 / Underlines come from local rules; a match does not establish AI authorship.
- 选区快捷键用于逐条检查。卡片上的 AI 改写处理问题所在的整段。 / The selection shortcut reviews findings. AI rewrite from a card processes the paragraph containing the finding.
- 模型需兼容已实现的三种接口格式，不能承诺“任何模型”都能接入。 / Models must support one of the three implemented API formats; do not promise compatibility with every model.
- 改写会发送正文、命中提示、有效词库条目和技能正文。是否本地处理取决于实际配置的服务。 / Rewrites send the text, finding hints, valid lexicon entries and skill body. Processing stays local only when the configured service runs locally.
- 词库和技能是交给模型的指导，改写结果需要用户对照审核。 / Lexicon entries and skills guide the model; users review the result before applying it.

## 媒体 / Media

- [GIF](deai-demo.gif)：用于 README 内联演示。 / Inline README demo.
- [MP4](deai-demo.mp4)：完整视频。 / Full video.

视频中的“接入任意模型”按上述接口兼容范围理解。应用适配分镜使用[原创通用 SVG](icons/README.md)，保留应用文字标签，不使用官方应用图标。
The video's “Bring any model” line refers to models compatible with those API formats. The compatibility scene uses [original generic SVG symbols](icons/README.md) with app-name labels, rather than official app icons.
