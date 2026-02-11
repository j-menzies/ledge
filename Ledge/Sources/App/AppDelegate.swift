import AppKit
import SwiftUI
import os.log

/// AppKit delegate that manages the LedgePanel lifecycle.
///
/// The AppDelegate is responsible for:
/// 1. Creating the DisplayManager
/// 2. Detecting the Xeneon Edge on launch
/// 3. Creating and displaying the widget panel
/// 4. Managing the panel content (widget dashboard)
class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: "com.ledge.app", category: "AppDelegate")

    /// The display manager — shared with the settings UI via @EnvironmentObject.
    let displayManager = DisplayManager()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Ledge starting up...")

        // Attempt to detect the Xeneon Edge and show the panel
        displayManager.detectXenonEdge()

        if displayManager.xeneonScreen != nil {
            displayManager.showPanel()

            // Set the initial dashboard content
            let dashboardView = DashboardView()
                .environmentObject(displayManager)
            displayManager.setPanelContent(dashboardView)

            // Start the touch remapper (will prompt for Accessibility permissions if needed)
            displayManager.startTouchRemapper()

            // Start in calibration mode so the first touch identifies the device
            if displayManager.isTouchRemapperActive {
                displayManager.calibrateTouch()
            }

            logger.info("Panel displayed on Xeneon Edge")
        } else {
            logger.warning("Xeneon Edge not found on launch — panel not shown")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Ledge shutting down")
        displayManager.stopTouchRemapper()
        displayManager.destroyPanel()
    }

    /// Keep the app running when all windows are closed (the panel is still active).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
