import SwiftUI

/// Main entry point for the Ledge application.
///
/// Uses SwiftUI App lifecycle but bridges to AppKit via AppDelegate for
/// NSPanel management and display detection.
@main
struct LedgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window — appears on the primary display.
        // ThemeManager is passed via .environment() — SettingsView observes
        // it directly and derives the theme, so changes propagate live.
        Window("Ledge Settings", id: "settings") {
            SettingsView(
                layoutManager: appDelegate.layoutManager,
                configStore: appDelegate.configStore
            )
            .environmentObject(appDelegate.displayManager)
            .environment(appDelegate.themeManager)
        }
        .defaultSize(width: 800, height: 650)
    }
}
