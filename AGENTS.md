# DeAI 项目说明

## 代理偏好
- 委派 Codex 子代理（T3 `delegate_task`）时统一使用：provider `codex`，model `gpt-6.1-sol`，options `{"reasoningEffort": "high", "serviceTier": "priority"}`（快速模式）。
- 后续开发完成后自主验证迭代，可以把 BUG测试，性能测试等任务委派 codex 子代理进行 computer use 的实际操作来验证

## 构建与验证
- Rust：`source ~/.cargo/env`；`cd core && cargo test --workspace`
- WASM：`cd core/crates/deai-wasm && wasm-pack build --target nodejs && node tests/smoke.mjs`
- Apple 库：`./core/scripts/build-apple.sh`
- Mac 应用：`cd mac && xcodegen && xcodebuild -project DeAI.xcodeproj -scheme DeAI build` / `test`
- AX 探针：`cd tools/ax-probe && swift build && .build/debug/ax-probe <delay> [bundleId]`

## 已知事项
- 所有 Finding 偏移统一为 UTF-16 code unit。
- AX：系统级 `AXUIElementCreateSystemWide()` 取焦点元素会返回 -25204（CannotComplete），需改用 `AXUIElementCreateApplication(pid)`。
- Word 16.113（2026-10 实测）：正文 AXTextArea 在窗口树第 10 层（AXDescription「页面 N 内容」，可能每页一个），焦点常落在 AXSplitGroup/AXScrollArea，需向下搜索；正文元素首次可能未出现（懒加载）。支持 AXBoundsForRange 逐字矩形、AXReplaceRangeWithText、实时 AXValue。段落分隔为 LF（TextEdit 为 CR）；AXRangeForPosition 在 Word 返回插入点（len=0）。偏移为 UTF-16。
