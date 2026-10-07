import AppKit
import SwiftUI

@main
struct DeAIApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("DeAI", systemImage: "text.badge.checkmark") {
            Button("Open Test Window") {
                openWindow(id: "test")
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        Window("DeAI Test", id: "test") {
            ContentView()
        }
    }
}
