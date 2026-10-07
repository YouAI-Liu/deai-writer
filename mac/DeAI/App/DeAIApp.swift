import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_: Notification) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--ui-capture"), index + 1 < arguments.count {
            DebugUICapture.start(directory: arguments[index + 1])
            return
        }
        if arguments.contains("--ui-preview") {
            DebugUIWindow.open()
            return
        }
        #endif
        controller.start()
    }

    func applicationWillTerminate(_: Notification) {
        controller.stop()
    }
}

@main
struct DeAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("DeAI", systemImage: "text.badge.checkmark") {
            MenuContent(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)
        Window("设置", id: "settings") {
            SettingsView(
                settings: appDelegate.controller.settings,
                currentBundleId: appDelegate.controller.frontmostBundleId
            )
        }
        Window("调试：规则测试窗口", id: "debug") {
            ContentView()
        }
        #if DEBUG
        Window("UI 预览", id: "ui-preview") {
            DebugUIShowcase()
        }
        #endif
    }
}

struct MenuContent: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    init(controller: AppController) {
        self.controller = controller
        _settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("DeAI").font(DeAIDesign.font(22, weight: .semibold)).tracking(-0.7)
                Spacer()
            }
            Toggle("自动下划线", isOn: $settings.autoUnderline)
                .toggleStyle(DeAIToggleStyle(inverted: true))
            if let bundleId = controller.frontmostBundleId {
                Button {
                    controller.toggleCurrentApp()
                } label: {
                    HStack {
                        Text(settings.isAppEnabled(bundleId)
                             ? "在 \(appName(bundleId)) 中停用" : "在 \(appName(bundleId)) 中启用")
                            .lineLimit(2)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
            VStack(spacing: 16) {
                menuButton("设置") { openWindow(id: "settings") }
                menuButton("规则测试窗口") { openWindow(id: "debug") }
                #if DEBUG
                menuButton("UI 预览") { openWindow(id: "ui-preview") }
                #endif
                menuButton("退出 DeAI") { NSApp.terminate(nil) }
            }
        }
        .font(DeAIDesign.font(12))
        .foregroundStyle(DeAIDesign.paper)
        .padding(24).frame(width: 300)
        .background(DeAIDesign.ink, in: RoundedRectangle(cornerRadius: DeAIDesign.radius))
        .preferredColorScheme(.dark)
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func appName(_ bundleId: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first?.localizedName ?? bundleId
    }
}
