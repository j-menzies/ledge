import SwiftUI

/// Main entry point for the Ledge application.
///
/// Uses SwiftUI App lifecycle but bridges to AppKit via AppDelegate for
/// NSPanel management and display detection.
@main
struct LedgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window — appears on the primary display
        Window("Ledge Settings", id: "settings") {
            SettingsView()
                .environmentObject(appDelegate.displayManager)
        }
        .defaultSize(width: 600, height: 400)
    }
}
