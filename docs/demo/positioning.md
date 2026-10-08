# DeAI 产品定位 / Positioning

用于 README 开头的“为什么做 DeAI”部分和演示视频脚本。不点名任何具体产品。
Used for the README "Why DeAI" section and the demo video script. Never name specific products.

每条主张都对应代码里已经实现的功能（括号内），不写没有实现的能力。
Every claim maps to an implemented feature (in brackets); do not claim anything beyond it.

---

## 中文

### 现在用 AI 去“AI 味”，有三个痛点

1. **技能往往要经过 Agent 才能用。** 不少改写技能是写给对话式 Agent 的，想用就得把文字复制进对话框、等它跑完、再复制回来，打断写作。
2. **常常只看到最终结果，看不到过程。** 交给 AI 的是一整段，拿回来的也是一整段，中间判断了什么、为什么改，一概不知。
3. **不知道具体改了哪里。** 除非专门要求“把改动标红”，否则往往要逐字对比原文和结果，很难放心地直接用。

### DeAI 的做法

1. **边写边看，选哪句改哪句。** 在 Word、备忘录等通过辅助功能提供文字的输入框里（浏览器需在设置中开启），打字时就在有问题的词句下面画线，点一下看到建议、一键替换；选中一段按快捷键，就只检查和改写这一段。（系统级下划线与建议卡片、选中检查快捷键、卡片上的 AI 改写）
2. **每一处改动都看得见。** 本地建议精确到具体词句，悬停类别标签可以看到为什么要改；AI 改写的结果和原文上下对照，改动能拆成词语替换时逐条列出。（建议卡片的规则说明、改写面板原文/改写对照与改动列表）
3. **技能可以自定义，不用经过 Agent。** 直接导入你自己的改写技能（Markdown / SKILL.md），按中文、英文分别指定，改写时自动选用。（改写技能：导入、语言标签、按语言选用）
4. **记住你的写法。** 觉得某个词改成另一个更顺手，一键“记住此改法”加入个人词库；以后打字时直接提示，AI 改写也会遵守。（个人词库：替换 / 避免 / 保留，卡片与改写面板里的“记住改法”）
5. **专门去除“机械味”。** 内置中英文 AI 腔规则：中文看 AI 习惯的句式和位置（段首空洞评论、提示性冒号、刻意对比、顿号堆砌、名词化翻译腔等），英文抓 AI 高频词、套话和对话残留，另外清理从 AI 对话里带出来的 Markdown 符号。规则基于人类文章与模型输出的对比整理，改写提示词要求只改有 AI 痕迹的地方，保留事实和原意。（中英文 AI 腔规则、Markdown 清理、改写安全规则）
6. **本地优先，保护隐私。** 日常检查全部在本机完成；只有你主动触发改写时，才会把那一段文字发给你自己配置的 AI 服务，Key 存在钥匙串里。（本地 Rust 规则引擎、钥匙串）

**让文字读起来像你写的，而不是 AI。**

---

## English

### Removing "AI tone" with AI today has three pain points

1. **Skills often work only through an agent.** Many rewriting skills are written for chat agents: copy your text into a chat, wait, copy it back — your writing flow breaks every time.
2. **You often see only the final result.** A whole paragraph goes in, a whole paragraph comes out. What was judged, and why, stays invisible.
3. **You can't tell what changed.** Unless you explicitly ask for changes to be highlighted, you have to diff the text by eye before you can trust it.

### What DeAI does instead

1. **See issues as you type; fix the sentence you pick.** In Word, Notes and other text fields that expose their text through Accessibility (browsers can be enabled in Settings), problem phrases are underlined as you write. Click for a suggestion and apply it in one step, or select a passage and press the hotkey to check and rewrite just that part.
2. **Every change is visible.** Local suggestions point at the exact phrase; hover the category tag to see why. The AI rewrite appears below the original for comparison, and when the change splits into word swaps, each one is listed.
3. **Bring your own skills — no agent required.** Import your own rewriting skill (Markdown / SKILL.md), assign it to Chinese or English text, and DeAI uses it automatically.
4. **It remembers how you write.** Prefer one word over another? "Remember this edit" adds it to your personal lexicon; DeAI flags it as you type and AI rewrites follow it.
5. **Built to remove the machine feel.** Built-in AI-tone rules look at where Chinese text uses AI-typical patterns (hollow paragraph openers, prompt-style colons, forced contrasts, stacked enumerations, nominalized translationese) and catch overused English AI vocabulary, stock phrases and chat leftovers, plus Markdown residue copied from AI chats — and the rewrite prompt asks the model to change only what reads as AI and keep facts and meaning.
6. **Local-first and private.** Everyday checks run entirely on your Mac. Text is sent to the AI provider you configure only when you trigger a rewrite, and keys live in the Keychain.

**Make your writing sound like you, not AI.**
