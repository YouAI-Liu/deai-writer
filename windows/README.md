# DeAI Windows 客户端（x64 实验版）

Windows 客户端独立于 `mac/`，使用 .NET 8 WPF 托盘 UI、UI Automation 3 COM 和原有 Rust 检查引擎；不改变 Swift 客户端、macOS 构建、安装包或 TCC 行为。

## 构建

前提：Windows x64、.NET 8 SDK、Rust MSVC stable（含 rustfmt/clippy）、Visual Studio Build Tools 的 **Desktop development with C++** 与 Windows SDK；安装包需要 Inno Setup 6.4+（本次使用 6.7.3，请遵守其许可）。Rust/cargo 与 dotnet 必须在 PATH 上。

从仓库根目录运行 PowerShell：

```powershell
./windows/scripts/build.ps1 -Test -Installer
```

脚本通过 vswhere/vcvars64 初始化 MSVC，构建 `deai-native` release DLL，执行整个 Rust 工作区测试、.NET 构建/格式检查、单元测试与跨进程 WPF UIA fixture，最后生成 self-contained `win-x64` 客户端与安装程序。UIA 回归需要已登录的交互桌面；无交互桌面的 CI 使用 `-SkipUia`，不会据此声称 UIA 通过。

```powershell
# 快速 .NET 回归（先构建 Rust DLL）
dotnet build windows/DeAI.sln -c Release
windows/DeAI.Tests/bin/x64/Release/net8.0-windows/DeAI.Tests.exe --unit
# UIA fixture 回归
windows/DeAI.Tests/bin/x64/Release/net8.0-windows/DeAI.Tests.exe windows/DeAI.Fixture/bin/x64/Release/net8.0-windows/DeAI.Fixture.exe
```

产物仅在 `windows/artifacts/`（gitignored）：`win-x64/DeAI.exe`、`deai_native.dll` 和 `DeAI-Windows-x64-0.1.0-Setup.exe`。安装按用户写入 `%LOCALAPPDATA%\Programs\DeAI`，无需管理员/.NET runtime；可选桌面快捷方式与登录启动，默认不启用。卸载保留用户设置/词库/密钥，避免误删；需要清除时先在设置中删除密钥，再手动删除 `%LOCALAPPDATA%\DeAI`。运行时禁止升级/卸载，先退出托盘客户端。当前安装包未签名，SmartScreen 可能提示；没有自动发布流程。

## 使用

1. 启动后打开设置；托盘菜单提供设置、检查/改写和退出。
2. 在目标编辑框中放置光标。`Ctrl+Alt+F9` 检查，`Ctrl+Alt+F10` 改写；可在设置中修改。冲突时拒绝变更，保留原快捷键。
3. 本地检查约每 1.2 秒读取当前焦点；不遍历其他应用、不发送网络请求。建议卡可以定位/选区、复制、忽略、禁用规则或对受支持目标应用应用替换。
4. 改写使用明确选区；空选区只扩展到光标所在段落，不默认发送整篇。范围上限 4000 UTF-16 单位。每次点击「发送并改写」前显示原文、服务主机和模型，预览后再接受写回。服务失败/取消/原文变化时不写回。
5. 设置包含语言、检查类别、三级灵敏度、排除应用、禁用规则、词库、Skills、服务和密钥。语言切换后重新打开窗口以刷新全部文案。

个人词库支持 replace/avoid/keep、exact/caseInsensitive/wholeWord，最多 200 条，每项词语/替换文本最多 100 UTF-16 单位；使用与 macOS 相同的 Rust 匹配逻辑。Skills 支持 SKILL.md 文件/目录导入、新建、编辑、删除与中文/英文默认选择；支持 `name`、`description`、`language: zh|en|any` 简单 frontmatter，最多 60000 UTF-16 单位。Skills 仅注入写作提示，不执行脚本/工具，内置 Skill 不可删除。

AI 支持 OpenAI Chat Completions、Responses、Anthropic Messages 和兼容的自定义 HTTPS 服务（loopback 调试可用 HTTP），拒绝重定向。OpenRouter 预设默认选择 `openrouter/free` 并开启「仅免费模型」，请求强制 `provider.max_price.prompt=0`、`completion=0`，拒绝付费模型；免费模型的限流、可用性、第三方数据保留策略以 OpenRouter 为准。自动化测试使用合成文本与模拟 HTTP，不依赖密钥、不自动调用真实服务。

密钥单独存放在 `%LOCALAPPDATA%\DeAI\provider-key.dpapi`，用 DPAPI **CurrentUser** 加密；不会进入 settings.json/源码/日志。DPAPI 不防同用户恶意进程，不是通用跨平台同步密钥方案。替换服务地址但保留已有密钥时需要确认。

## 安全边界与兼容范围

所有 finding/选区都是 **UTF-16 code unit offsets**。选区定位通过真实 UIA range prefix 文本计数，不把 UIA Character 移动数当作 UTF-16 偏移；emoji 不可拆分。写回前重新检查 RuntimeId、控件状态、原文与 ValuePattern 值，写回后再次读取验证；不使用剪贴板/模拟按键写回。

| 目标 | 本次验证 / 策略 |
| --- | --- |
| 合成 WPF TextBox | 已验证读取 → Rust 检查 → emoji/CRLF 选区/定位 → ValuePattern 安全写回与原文变更拒绝 |
| 合成 PasswordBox | 拒绝读取 |
| 合成 RichTextBox / Document | 只读、定位；拒绝自动写回，防止破坏格式 |
| Win32 Edit | 实现受限 ValuePattern 写回，**第三方应用尚未验证** |
| Word / Office / Notepad / 第三方编辑器 | **未验证，不承诺兼容**；只支持满足安全能力判定的目标 |
| Chrome / Edge / Firefox 等浏览器 | 默认不读取；设置可实验性开启，但浏览器/富文本写回未验证 |
| 终端、常见密码管理器、DeAI 自身 | 按进程策略排除；任意 UIA 密码字段也会拒绝 |
| 提权窗口、安全桌面、远程桌面断开/锁屏 | 未验证/可能不可访问，不请求 uiAccess 或管理员权限 |
| Windows ARM64、Windows 10/11 实机、多显示器/混合 DPI | 未验证；本次构建/fixture 在 Windows Server 2022 x64 交互 VM 验证 |

UIA 调用在独立 MTA 线程执行，配置连接/事务超时；但第三方 provider 仍可能不响应。屏幕矩形按 UIA 的物理像素绘制，进程使用 PerMonitorV2；混合 DPI 需另行验证。控件缺少安全写入能力时只允许复制建议，不能以盲目粘贴绕过。全值替换可能影响目标应用 Undo/光标行为，需要逐应用验证。

## 原生桥接

`core/crates/deai-native` 独立新增 C ABI，不改 UniFFI/WASM。`deai_check_json(ptr,len)` 接收 UTF-8 JSON（text/options/entries），返回拥有的 JSON C 字符串；调用方必须用 `deai_free_json` 释放，不能用其他 allocator。请求最多 4 MB、文本最多 100000 UTF-16 单位。异常/panic 不穿过 ABI，错误以 JSON 返回。C# wrapper 验证结果范围并释放 Rust 分配的响应。
