import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_: Notification) {
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
        Window("设置", id: "settings") {
            SettingsView(
                settings: appDelegate.controller.settings,
                currentBundleId: appDelegate.controller.frontmostBundleId
            )
        }
        Window("调试：规则测试窗口", id: "debug") {
            ContentView()
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    init(controller: AppController) {
        self.controller = controller
        _settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        Toggle("自动下划线", isOn: $settings.autoUnderline)
        Divider()
        if let bundleId = controller.frontmostBundleId {
            Button(
                settings.isAppEnabled(bundleId)
                    ? "在 \(appName(bundleId)) 中停用" : "在 \(appName(bundleId)) 中启用"
            ) {
                controller.toggleCurrentApp()
            }
        }
        Divider()
        Button("设置…") { openWindow(id: "settings") }
        Button("调试：规则测试窗口") { openWindow(id: "debug") }
        Divider()
        Button("退出") { NSApp.terminate(nil) }
    }

    private func appName(_ bundleId: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first?.localizedName ?? bundleId
    }
}
