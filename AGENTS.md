# DeAI 项目说明

## 代理偏好
- 委派 Codex 子代理（T3 `delegate_task`）时统一使用：provider `codex`，model `gpt-6.1-sol`，options `{"reasoningEffort": "high", "serviceTier": "priority"}`（快速模式）。
- 后续开发完成后自主验证迭代，可以把 BUG测试，性能测试等任务委派 codex 子代理进行 computer use 的实际操作来验证

## Git
- 远程：https://github.com/YouAI-Liu/deai-writer（私有），分支 main。
- 未配置全局 git 身份；提交用 `git -c user.name="YouAI-Liu" -c user.email="319323242+YouAI-Liu@users.noreply.github.com" commit ...`。
- 推送用 gh 凭证（钥匙串里可能有别的账号）：`git -c credential.helper= -c credential.helper='!gh auth git-credential' push`，推送前确认 `gh auth status` 活跃账号为 YouAI-Liu。

## 构建与验证
- Rust：`source ~/.cargo/env`；`cd core && cargo test --workspace`
- WASM：`cd core/crates/deai-wasm && wasm-pack build --target nodejs && node tests/smoke.mjs`
- Apple 库：`./core/scripts/build-apple.sh`
- Mac 应用：`cd mac && xcodegen && xcodebuild -project DeAI.xcodeproj -scheme DeAI build` / `test`
- 安装（稳定路径，TCC 辅助功能权限按签名+路径记住授权）：`xcodebuild -project DeAI.xcodeproj -scheme DeAI -configuration Release build && rsync -a --delete ~/Library/Developer/Xcode/DerivedData/DeAI-*/Build/Products/Release/DeAI.app/ ~/Applications/DeAI.app/`（两端必须带尾斜杠，否则会嵌套成 DeAI.app/DeAI.app 而旧包不变；安装后用 `codesign -dv` 核对 CDHash 与 Release 产物一致）；签名身份由 git-ignored `mac/Local.xcconfig` 提供（参考 `Local.xcconfig.example`，缺失时回退 ad-hoc）
- AX 探针：`cd tools/ax-probe && swift build && .build/debug/ax-probe <delay> [bundleId]`

## 已知事项
- TCC 授权按 bundle id + designated requirement 记录：绝不要以 release bundle id 启动 DerivedData 构建（Debug 构建固定为 `com.local.deai.debug`）。若权限看似失效，`tccutil reset Accessibility com.local.deai` 后重新授权。
- 所有 Finding 偏移统一为 UTF-16 code unit。
- AX：系统级 `AXUIElementCreateSystemWide()` 取焦点元素会返回 -25204（CannotComplete），需改用 `AXUIElementCreateApplication(pid)`。
- Word 16.113（2026-10 实测）：正文 AXTextArea 在窗口树第 10 层（AXDescription「页面 N 内容」，可能每页一个），焦点常落在 AXSplitGroup/AXScrollArea，需向下搜索；正文元素首次可能未出现（懒加载）。支持 AXBoundsForRange 逐字矩形、AXReplaceRangeWithText、实时 AXValue。段落分隔为 LF（TextEdit 为 CR）；AXRangeForPosition 在 Word 返回插入点（len=0）。偏移为 UTF-16。
- Word 分页模型（QA 第二轮验证）：每页一个 AXTextArea，AXValue 只含该页文本，但 AXNumberOfCharacters、AXBoundsForRange、AXSelectedTextRange、AXVisibleCharacterRange 全部使用全文档偏移；`AXSharedCharacterRange` 给出该页在共享文本中的 {location, length}（已实测：{0,3206} + {3206,3203} + {6409,192} = 6601），`AXSharedTextUIElements` 列出全部页。页面元素的懒加载需要窗口内命中测试（AXUIElementCopyElementAtPosition）等材料化手段 —— 仅设置 AXManualAccessibility 不一定够。
