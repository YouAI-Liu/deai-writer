#if DEBUG
import AppKit
import SwiftUI

/// Uses the production views with an in-memory replacement for visual QA.
struct DebugUIShowcase: View {
    @StateObject private var model = SuggestionCardModel(finding: sample, matchedText: "说白了，")
    @StateObject private var settings = AppSettings(userDefaults: UserDefaults(suiteName: "deai.ui-preview")!)
    @State private var page = "建议"
    @State private var reduced = false
    @State private var darkHost = false
    @State private var applications = 0

    private static let sample = Finding(
        category: .aiToneZh, ruleId: "zh.banned_opener", message: "删掉套话，直接说重点。",
        start: 0, end: 4, suggestions: [""], tier: 1
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                ForEach(["建议", "设置", "权限", "规则窗口"], id: \.self) { title in
                    Button(title) { page = title }.buttonStyle(.plain)
                        .foregroundStyle(page == title ? DeAIDesign.ink : DeAIDesign.muted)
                }
                Spacer()
            }
            .font(DeAIDesign.font(12, weight: .medium)).padding(20)
            Divider()
            Group {
                switch page {
                case "设置": SettingsView(settings: settings, currentBundleId: "com.apple.TextEdit")
                case "权限": PermissionView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case "规则窗口": ContentView()
                default: cardStage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 790)
        .background(DeAIDesign.canvas)
        .preferredColorScheme(.light)
        .onAppear {
            model.onApply = { _, completion in
                applications += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { completion(true) }
            }
            model.onDismiss = { model.visible = false }
            model.onIgnore = { model.visible = false }
            model.onDisableRule = { model.visible = false }
        }
    }

    private var cardStage: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZStack(alignment: .top) {
                SuggestionCardView(model: model, autoDismiss: false)
                    .environment(\.deaiReducedMotionOverride, reduced ? true : nil)
                    .padding(.top, 64)
            }
            .frame(maxWidth: .infinity).frame(height: 410)
            .background(darkHost ? DeAIDesign.ink.opacity(0.9) : DeAIDesign.canvas)
            HStack(spacing: 12) {
                Button("待处理") { reset() }
                Button("应用中") { reset(); model.phase = .loading }
                Button("改写结果") { reset(); model.phase = .diff("") }
                Button("成功") { reset(); model.phase = .success }
                Button("长文本") {
                    let text = String(repeating: "长文本，", count: 400)
                    model.update(
                        finding: Finding(category: .markdown, ruleId: "md.bold", message: "Markdown 残留：加粗",
                                         start: 0, end: UInt32(text.utf16.count + 4), suggestions: [text], tier: 1),
                        matchedText: "**" + text + "**"
                    )
                }
            }
            .buttonStyle(DeAIButtonStyle(compact: true))
            HStack {
                Toggle("减少动态效果", isOn: $reduced)
                Toggle("深色宿主", isOn: $darkHost)
            }
            .toggleStyle(DeAIToggleStyle()).font(DeAIDesign.font(12))
            Text("替换调用：\(applications)").font(DeAIDesign.font(11)).foregroundStyle(DeAIDesign.muted)
            Spacer()
        }
        .padding(30)
    }

    private func reset() {
        model.update(finding: Self.sample, matchedText: "说白了，")
        model.visible = true
    }
}

final class DebugUIWindow {
    private static var window: NSWindow?

    static func open() {
        let host = NSHostingView(rootView: DebugUIShowcase())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 790),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "DeAI Debug — UI 预览"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
#endif

#if DEBUG
/// AppKit snapshots of the running SwiftUI views, without host-app permissions.
@MainActor
final class DebugUICapture {
    private static var active: DebugUICapture?
    private let directory: URL
    private let window: NSWindow
    private let model = SuggestionCardModel(
        finding: Finding(category: .markdown, ruleId: "md.bold", message: "Markdown 残留：加粗",
                         start: 0, end: 6, suggestions: ["粗体"], tier: 1),
        matchedText: "**粗体**"
    )
    private let controller = AppController()

    private init(directory: String) {
        self.directory = URL(fileURLWithPath: directory, isDirectory: true)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "DeAI Debug — 截图"
        window.isReleasedWhenClosed = false
    }

    static func start(directory: String) {
        let capture = DebugUICapture(directory: directory)
        active = capture
        Task { await capture.run() }
    }

    private func show<V: View>(_ view: V, size: NSSize) {
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func card(dark: Bool = false, reduced: Bool = false) -> some View {
        SuggestionCardView(model: model, autoDismiss: false)
            .environment(\.deaiReducedMotionOverride, reduced ? true : nil)
            .padding(.top, 74)
            .frame(width: 620, height: 500)
            .background(dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : DeAIDesign.canvas)
    }

    private func save(_ name: String, after delay: Double = 0.6) async throws {
        try await Task.sleep(for: .seconds(delay))
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        print("UI screenshot: \(name)")
    }

    private func scrollToBottom(in view: NSView?) {
        guard let view else { return }
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            document.scroll(NSPoint(x: 0, y: document.isFlipped ? document.bounds.maxY : 0))
            return
        }
        for child in view.subviews { scrollToBottom(in: child) }
    }

    private func run() async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            model.onDismiss = {}
            model.onApply = { _, completion in completion(true) }
            show(card(), size: NSSize(width: 620, height: 500))
            try await save("card-idle")
            model.phase = .loading
            try await save("card-loading")
            model.update(finding: model.finding, matchedText: model.matchedText)
            model.apply("粗体")
            model.apply("粗体")
            try await save("card-success-animation", after: 0.38)
            try await save("card-success")
            model.update(finding: model.finding, matchedText: model.matchedText)
            model.phase = .diff("")
            try await save("card-diff-structure")
            model.update(finding: model.finding, matchedText: model.matchedText)
            show(card(dark: true), size: NSSize(width: 620, height: 500))
            try await save("card-dark-host")
            show(card(reduced: true), size: NSSize(width: 620, height: 500))
            try await save("card-reduced-motion")
            model.phase = .success
            try await save("card-reduced-success")
            model.update(
                finding: Finding(category: .markdown, ruleId: "md.bold", message: "Markdown 残留：加粗",
                                 start: 0, end: 2004, suggestions: [String(repeating: "长文本，", count: 400)], tier: 1),
                matchedText: "**" + String(repeating: "长文本，", count: 400) + "**"
            )
            show(card(), size: NSSize(width: 620, height: 600))
            try await save("card-long-text")
            scrollToBottom(in: window.contentView)
            try await save("card-long-text-bottom")
            show(SettingsView(settings: controller.settings, currentBundleId: "com.apple.TextEdit"),
                 size: NSSize(width: 540, height: 700))
            try await save("settings")
            scrollToBottom(in: window.contentView)
            try await save("settings-rules")
            show(PermissionView(), size: NSSize(width: 420, height: 360))
            try await save("permission")
            show(MenuContent(controller: controller), size: NSSize(width: 300, height: 270))
            try await save("menu")
            show(ContentView(), size: NSSize(width: 700, height: 620))
            try await save("rule-window", after: 0.6)
            print("UI capture complete")
        } catch {
            print("UI capture failed: \(error)")
        }
        NSApp.terminate(nil)
    }
}
#endif
