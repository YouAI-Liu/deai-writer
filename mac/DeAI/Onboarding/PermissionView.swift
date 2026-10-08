import ApplicationServices
import SwiftUI

struct PermissionView: View {
    @Environment(\.deaiUILanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.t(.permissionTitle, lang))
                    .font(DeAIDesign.font(21, weight: .semibold)).tracking(-0.5)
                Text(L10n.t(.permissionBody, lang))
                    .font(DeAIDesign.font(12)).lineSpacing(3)
                    .foregroundStyle(DeAIDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L10n.t(.permissionNote, lang))
            .font(DeAIDesign.font(11))
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(DeAIDesign.surface, in: RoundedRectangle(cornerRadius: DeAIDesign.radius))
            Button {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            } label: {
                HStack {
                    Text(L10n.t(.openSystemSettings, lang))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(DeAIDesign.font(12, weight: .medium))
                }
            }
            .buttonStyle(DeAIButtonStyle())
        }
        .padding(24)
        .frame(width: 420, height: 360)
        .foregroundStyle(DeAIDesign.text)
        .background(DeAIDesign.background)
    }

}
