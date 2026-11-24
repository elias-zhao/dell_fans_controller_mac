import SwiftUI
import AppKit
import DellFansCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct DellFansApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(appState: appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "fanblades.fill")
                Text(appState.menuBarLabelText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)

        Window("Dell Fans Controller", id: "detail") {
            DetailWindowView(appState: appState)
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 780, height: 520)
    }
}
