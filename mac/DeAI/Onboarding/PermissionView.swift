import ApplicationServices
import SwiftUI

/// Accessibility-permission onboarding. Shown at launch when
/// `AXIsProcessTrusted()` is false; polls every second until granted.
struct PermissionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text("需要辅助功能权限")
                    .font(.title2.weight(.semibold))
            }
            Text("""
            DeAI 通过 macOS 辅助功能 API 读取前台应用中的文本,以便在你输入时标出语法、AI 腔和 Markdown 残留问题,并在屏幕上绘制下划线。

            DeAI 不会读取密码输入框等安全文本字段。
            """)
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("授权步骤:").font(.headline)
                Text("1. 点击下方按钮打开「隐私与安全性 → 辅助功能」")
                Text("2. 在列表中勾选 DeAI(可能需要解锁并输入密码)")
                Text("3. 授权后本窗口会自动关闭")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("打开系统设置") {
                    NSWorkspace.shared.open(
                        URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        )!
                    )
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
