# DeAI 优化交接（2026-10-12）

两阶段源码已完成本地自动验证；真实 Word 与交互现场验证尚未完成。

## 已实现

- 建议携带目标 key；窗口、文档与会话身份贯穿检查、卡片和写回，旧异步结果会被丢弃。
- 写入前核对目标、焦点、选区与原文快照；写后核对完整结果。剪贴板仅在仍属于本次操作时恢复，失败的菜单粘贴不再追加键盘粘贴。
- Word 使用全文 UTF-16 快照，页面只提供可见几何；跨页选区不再静默截断。缺页、重叠或不一致快照会停止操作。
- 改写差异默认全部采用，可逐项保留原文或全部保留。预览、复制和写回使用相同的最终文本；全部保留不执行写入。新结果会清除旧选择，标点、空白和 Unicode 编码均保留。
- 当前应用可暂停自动检查 15 分钟、立即恢复或到期恢复。暂停不改永久应用规则，不影响其他应用，手动选中检查仍可用；重启应用后临时暂停清除。

主要入口：`TextDocument.swift`、`TextReplacer.swift`、`RewriteReview.swift`、`RewritePanel.swift`、`AppPauseStore.swift` 和 `AppController.swift`。

## 本地验证

- Mac 全套：253 项，0 失败，1 项截图测试跳过；包含新增的 19 项写回保护与 14 项差异/暂停测试。
- Rust 工作区：125 项通过，4 项忽略；WASM 构建、smoke 与误报回归通过；Apple 核心库构建通过。
- 最终 Release 构建及 `codesign --verify --deep --strict` 验证通过。尚未安装、发版。
- 新增测试通过可控编辑器、独立剪贴板、随机 Unicode 往返和真实暂停计时器验证逻辑，不替代现场 Word 验证。

构建与测试依赖及完整命令见根目录 `AGENTS.md`。Mac 可执行：

```sh
cd mac
xcodegen
xcodebuild -project DeAI.xcodeproj -scheme DeAI -derivedDataPath build/qa test
xcodebuild -project DeAI.xcodeproj -scheme DeAI -configuration Release -derivedDataPath build/qa build
```

## 接手后的现场检查

此前 Mac 锁屏，以下场景未验证，不能据自动测试宣称通过：

1. Word 单页及跨页：全部采用、全部保留、混合选择；核对文字、选区、分页重排和格式保留。等待写入期间切文档或改选区，确认停止操作。
2. 长文本、中英文、标点、重复词与 emoji：差异、最终预览、复制和实际写入一致；检查列表滚动、窗口边缘、小屏幕和词库展开布局。
3. 暂停自动检查后立即隐藏提示，旧检查结果不再弹出；其他应用正常工作，手动检查可用；到期及手动恢复不重新启用永久关闭的应用。

调试钩子沿用 `AGENTS.md` 的启用方式。新增 action：`rewriteKeepChange` / `rewriteUseChange`（`index` 指定改动）、`rewriteUseAll` / `rewriteKeepAll`、`pauseCurrentApp` / `resumeCurrentApp`；状态新增 `finalText`、`acceptedEdits`、`changeCount`、`pausedApps`。

安装仍须遵守 `AGENTS.md` 的稳定路径和签名要求；不要直接启动构建目录中的 Release bundle。构建产物、日志、签名配置和原始 REA 分析产物不随源码同步。
