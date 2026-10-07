import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_: Notification) {
        // As the XCTest host the ad-hoc-signed Debug app gets a new signature
        // every build, so TCC never matches and AX would prompt on each run.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }
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
    @State private var groupsExpanded: Bool

    init(controller: AppController, groupsExpanded: Bool = false) {
        self.controller = controller
        _settings = ObservedObject(wrappedValue: controller.settings)
        _groupsExpanded = State(initialValue: groupsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("DeAI").font(DeAIDesign.titleFont(22)).tracking(-0.7)
                Spacer()
            }
            Toggle("自动下划线", isOn: $settings.autoUnderline)
                .toggleStyle(DeAIToggleStyle())
            // sensitive apps (terminals, password managers) are hard-excluded
            // — a toggle there would be a no-op, so hide the row entirely
            if let bundleId = controller.frontmostBundleId,
               AppGroup.group(for: bundleId) != .sensitive {
                Toggle(isOn: Binding(
                    get: { settings.isAppEnabled(bundleId) },
                    set: { on in
                        if on != settings.isAppEnabled(bundleId) {
                            controller.toggleCurrentApp()
                        }
                    }
                )) {
                    Text("在 \(appName(bundleId)) 中检查").lineLimit(2)
                }
                .toggleStyle(DeAIToggleStyle())
            }
            Rectangle().fill(DeAIDesign.border).frame(height: 0.5)
            // BUG-03: a SwiftUI Menu renders as a system pop-up button with
            // unreadable text on our custom surface — expand inline instead.
            Button {
                withAnimation(DeAIDesign.motion(false)) { groupsExpanded.toggle() }
            } label: {
                HStack {
                    Text("应用类型")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(DeAIDesign.font(10, weight: .semibold))
                        .foregroundStyle(DeAIDesign.muted)
                        .rotationEffect(.degrees(groupsExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if groupsExpanded {
                VStack(spacing: 12) {
                    ForEach(AppGroup.configurable, id: \.self) { group in
                        Toggle(group.displayName, isOn: groupBinding(group))
                            .toggleStyle(DeAIToggleStyle())
                    }
                }
                .font(DeAIDesign.font(11))
                .padding(.leading, 8)
            }
            Rectangle().fill(DeAIDesign.border).frame(height: 0.5)
            VStack(spacing: 16) {
                menuButton("设置") { controller.showSettingsWindow() }
                menuButton("规则测试窗口") { openWindow(id: "debug") }
                #if DEBUG
                menuButton("UI 预览") { openWindow(id: "ui-preview") }
                #endif
                menuButton("退出 DeAI") { NSApp.terminate(nil) }
            }
        }
        .font(DeAIDesign.font(12))
        .foregroundStyle(DeAIDesign.text)
        .padding(24).frame(width: 300)
        // fill the whole MenuBarExtra window edge to edge; the system window
        // already supplies the rounded corners and border
        .background(DeAIDesign.background.ignoresSafeArea())
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

    private func groupBinding(_ group: AppGroup) -> Binding<Bool> {
        Binding(
            get: {
                (settings.groupRules[group] ?? AppGroup.defaultRule(for: group)).enabled
            },
            set: { enabled in
                var rule = settings.groupRules[group]
                    ?? AppGroup.defaultRule(for: group)
                rule.enabled = enabled
                settings.groupRules[group] = rule
            }
        )
    }

    private func appName(_ bundleId: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first?.localizedName ?? bundleId
    }
}
