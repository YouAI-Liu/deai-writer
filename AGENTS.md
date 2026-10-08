# DeAI 项目说明

如存在 `AGENTS.local.md`（本地、不入库），请一并阅读并遵守。

## Git
- 仓库：https://github.com/YouAI-Liu/deai-writer，分支 main。

## 构建与验证
- Rust：`source ~/.cargo/env`；`cd core && cargo test --workspace`
- WASM：`cd core/crates/deai-wasm && wasm-pack build --target nodejs && node tests/smoke.mjs`
- Apple 库：`./core/scripts/build-apple.sh`
- Mac 应用：`cd mac && xcodegen && xcodebuild -project DeAI.xcodeproj -scheme DeAI build` / `test`
- 安装（稳定路径，TCC 辅助功能权限按签名+路径记住授权）：在 `mac/` 下执行 `xcodebuild -project DeAI.xcodeproj -scheme DeAI -configuration Release -derivedDataPath build/dd build && rsync -a --delete build/dd/Build/Products/Release/DeAI.app/ ~/Applications/DeAI.app/`（`build/` 已被 .gitignore 忽略）（两端必须带尾斜杠，否则会嵌套成 DeAI.app/DeAI.app 而旧包不变；安装后用 `codesign -dv` 核对 CDHash 与 Release 产物一致）；签名身份由 git-ignored `mac/Local.xcconfig` 提供（参考 `Local.xcconfig.example`，缺失时回退 ad-hoc）
- AX 探针：`cd tools/ax-probe && swift build && .build/debug/ax-probe <delay> [bundleId]`

## 已知事项
- TCC 授权按 bundle id + designated requirement 记录：绝不要以 release bundle id 启动 DerivedData 构建（Debug 构建固定为 `com.local.deai.debug`）。若权限看似失效，`tccutil reset Accessibility com.local.deai` 后重新授权。
- Debug/test host 是 ad-hoc 签名（每次构建签名都变，TCC 永不持久）：AppDelegate 在 XCTest 环境下直接跳过 `controller.start()`；不要指望 DeAI Debug 的辅助功能授权可保留。
- 所有 Finding 偏移统一为 UTF-16 code unit。
- AX：系统级 `AXUIElementCreateSystemWide()` 取焦点元素会返回 -25204（CannotComplete），需改用 `AXUIElementCreateApplication(pid)`。
- Word 16.113（2026-10 实测）：正文 AXTextArea 在窗口树第 10 层（AXDescription「页面 N 内容」，可能每页一个），焦点常落在 AXSplitGroup/AXScrollArea，需向下搜索；正文元素首次可能未出现（懒加载）。支持 AXBoundsForRange 逐字矩形、AXReplaceRangeWithText、实时 AXValue。段落分隔为 LF（TextEdit 为 CR）；AXRangeForPosition 在 Word 返回插入点（len=0）。偏移为 UTF-16。
- AI 改写 debug 钩子：启动参数 `-deai.debugStatePath <path>` 同时启用 DistributedNotificationCenter `com.local.deai.debug.command`（action: showCard/apply/ignore/disableRule/dismissCard/rewriteFinding/rewriteHotkey/rewriteAccept/rewriteCancel，userInfo 带 ruleId/index/suggestion）；再传 `-deai.debugMockRewrite <text>` 可让改写请求跳过网络直接返回该文本。状态 JSON 含 `card` 与 `rewrite` 字段。
- Word 分页模型（QA 第二轮验证）：每页一个 AXTextArea，AXValue 只含该页文本，但 AXNumberOfCharacters、AXBoundsForRange、AXSelectedTextRange、AXVisibleCharacterRange 全部使用全文档偏移；`AXSharedCharacterRange` 给出该页在共享文本中的 {location, length}（已实测：{0,3206} + {3206,3203} + {6409,192} = 6601），`AXSharedTextUIElements` 列出全部页。页面元素的懒加载需要窗口内命中测试（AXUIElementCopyElementAtPosition）等材料化手段 —— 仅设置 AXManualAccessibility 不一定够。
