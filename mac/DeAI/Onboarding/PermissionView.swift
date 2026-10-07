import ApplicationServices
import SwiftUI

struct PermissionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text("辅助功能权限")
                    .font(DeAIDesign.font(21, weight: .semibold)).tracking(-0.5)
                Text("DeAI 需要读取前台文本，以标出语法、AI 腔和 Markdown 残留；密码等安全输入框会跳过。")
                    .font(DeAIDesign.font(12)).lineSpacing(3)
                    .foregroundStyle(DeAIDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("在辅助功能列表中勾选 DeAI，按系统提示解锁。")
                Text("授权后，此窗口会自动关闭。")
            }
            .font(DeAIDesign.font(11))
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(DeAIDesign.paper, in: RoundedRectangle(cornerRadius: 18))
            Button {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            } label: {
                HStack {
                    Text("打开系统设置")
                    Spacer()
                    Image(systemName: "arrow.up.right").font(DeAIDesign.font(12, weight: .medium))
                }
            }
            .buttonStyle(DeAIButtonStyle())
        }
        .padding(24)
        .frame(width: 420, height: 360)
        .foregroundStyle(DeAIDesign.ink)
        .background(DeAIDesign.canvas)
        .preferredColorScheme(.light)
    }

}
