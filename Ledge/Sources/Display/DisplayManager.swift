import AppKit
import SwiftUI
import Combine
import os.log

/// Manages detection of the Xeneon Edge display and the lifecycle of the LedgePanel.
///
/// DisplayManager watches for display configuration changes (connect/disconnect/rearrange)
/// and automatically creates or repositions the LedgePanel when the Xeneon Edge is found.
@MainActor
class DisplayManager: ObservableObject {

    // MARK: - Published State

    /// The current panel, if the Xeneon Edge is connected and the panel is active.
    @Published private(set) var panel: LedgePanel?

    /// The detected Xeneon Edge screen, if connected.
    @Published private(set) var xeneonScreen: NSScreen?

    /// Whether the panel is currently displayed.
    @Published private(set) var isActive: Bool = false

    /// Status message for the settings UI.
    @Published private(set) var statusMessage: String = "Searching for Xeneon Edge..."

    // MARK: - Configuration

    /// Known characteristics of the Xeneon Edge display.
    enum XenonEdgeInfo {
        static let width: CGFloat = 2560
        static let height: CGFloat = 720
        static let displayName = "XENEON EDGE"
    }

    // MARK: - Touch Remapping

    /// The touch remapper that fixes macOS's incorrect touchscreen-to-display mapping.
    let touchRemapper = TouchRemapper()

    /// Whether the touch remapper is active and remapping events.
    @Published private(set) var isTouchRemapperActive: Bool = false

    /// Status of the touch remapper for the settings UI.
    @Published private(set) var touchStatus: String = "Not started"

    // MARK: - Private

    private let logger = Logger(subsystem: "com.ledge.app", category: "DisplayManager")
    private var displayReconfigurationToken: Any?

    // MARK: - Lifecycle

    init() {
        registerForDisplayChanges()
        detectXenonEdge()
    }

    deinit {
        // Cleanup is handled by ARC; the reconfiguration callback is managed by the system
    }

    // MARK: - Display Detection

    /// Scan connected screens to find the Xeneon Edge.
    func detectXenonEdge() {
        let screens = NSScreen.screens

        logger.info("Scanning \(screens.count) connected screen(s) for Xeneon Edge...")

        // Strategy 1: Match by resolution (2560×720 is very distinctive)
        if let match = screens.first(where: { isXenonEdgeByResolution($0) }) {
            foundXenonEdge(match, method: "resolution")
            return
        }

        // Strategy 2: Match by display name (from IOKit display info)
        if let match = screens.first(where: { isXenonEdgeByName($0) }) {
            foundXenonEdge(match, method: "name")
            return
        }

        // Not found
        xeneonScreen = nil
        isActive = false
        statusMessage = "Xeneon Edge not detected. Connect the display and it will be detected automatically."
        logger.warning("Xeneon Edge not found among \(screens.count) screen(s)")

        // Log available screens for debugging
        for (index, screen) in screens.enumerated() {
            let frame = screen.frame
            let name = screen.localizedName
            logger.info("  Screen \(index): \(name) — \(Int(frame.width))×\(Int(frame.height))")
        }
    }

    /// Manually select a screen to use (fallback when auto-detection fails).
    func selectScreen(_ screen: NSScreen) {
        foundXenonEdge(screen, method: "manual selection")
    }

    // MARK: - Panel Management

    /// Show the panel on the Xeneon Edge.
    func showPanel() {
        guard let screen = xeneonScreen else {
            logger.error("Cannot show panel: no Xeneon Edge screen detected")
            return
        }

        if panel == nil {
            panel = LedgePanel(on: screen)
            logger.info("Created LedgePanel on Xeneon Edge")
        }

        panel?.makeKeyAndOrderFront(nil)
        isActive = true
        statusMessage = "Active on \(screen.localizedName)"
        logger.info("Panel is now visible on Xeneon Edge")
    }

    /// Hide the panel (but keep the screen reference).
    func hidePanel() {
        panel?.orderOut(nil)
        isActive = false
        statusMessage = "Panel hidden (Xeneon Edge still connected)"
        logger.info("Panel hidden")
    }

    /// Completely tear down the panel.
    func destroyPanel() {
        panel?.orderOut(nil)
        panel = nil
        isActive = false
        logger.info("Panel destroyed")
    }

    /// Set the SwiftUI content view on the panel.
    func setPanelContent<Content: View>(_ content: Content) {
        guard let panel else {
            logger.error("Cannot set content: panel not created")
            return
        }

        let hostingView = NSHostingView(rootView: content)
        panel.contentView = hostingView
    }

    // MARK: - Display Change Notifications

    private func registerForDisplayChanges() {
        // Watch for screen configuration changes (connect/disconnect/rearrange)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Hop back to MainActor to satisfy Swift 6 concurrency
            Task { @MainActor in
                self?.handleDisplayChange()
            }
        }
    }

    private func handleDisplayChange() {
        logger.info("Display configuration changed, re-scanning...")

        let previousScreen = xeneonScreen
        detectXenonEdge()

        if let currentScreen = xeneonScreen {
            if currentScreen != previousScreen {
                // Screen changed (e.g., rearranged) — reposition
                logger.info("Xeneon Edge repositioned, updating panel frame")
                panel?.reposition(on: currentScreen)
            }
        } else if previousScreen != nil {
            // Xeneon Edge was disconnected
            logger.info("Xeneon Edge disconnected")
            destroyPanel()
            statusMessage = "Xeneon Edge disconnected. Waiting for reconnection..."
        }
    }

    // MARK: - Touch Remapper Management

    /// Start the touch remapper. Requires Accessibility permissions.
    func startTouchRemapper() {
        guard let screen = xeneonScreen else {
            touchStatus = "Cannot start: Xeneon Edge not detected"
            return
        }

        if !touchRemapper.checkAccessibilityPermissions() {
            touchRemapper.requestAccessibilityPermissions()
            touchStatus = "Waiting for Accessibility permission..."
            return
        }

        touchRemapper.start(targetScreen: screen)
        isTouchRemapperActive = touchRemapper.isActive
        touchStatus = touchRemapper.isActive ? "Active — remapping touch to Xeneon Edge" : "Failed to start"
    }

    /// Stop the touch remapper.
    func stopTouchRemapper() {
        touchRemapper.stop()
        isTouchRemapperActive = false
        touchStatus = "Stopped"
    }

    /// Start calibration — ask the user to touch the Xeneon Edge so we can
    /// learn which HID device ID corresponds to the touchscreen.
    func calibrateTouch() {
        guard touchRemapper.isActive else {
            touchStatus = "Start the remapper first"
            return
        }

        touchRemapper.startLearning()
        touchStatus = "Calibrating — touch the Xeneon Edge screen..."

        touchRemapper.onLearningComplete = { [weak self] in
            Task { @MainActor in
                self?.touchStatus = "Calibrated — touch remapping active"
            }
        }
    }

    // MARK: - Detection Helpers

    private func isXenonEdgeByResolution(_ screen: NSScreen) -> Bool {
        let size = screen.frame.size
        // Check for the Xeneon Edge's distinctive 2560×720 resolution
        return size.width == XenonEdgeInfo.width && size.height == XenonEdgeInfo.height
    }

    private func isXenonEdgeByName(_ screen: NSScreen) -> Bool {
        let name = screen.localizedName
        return name.localizedCaseInsensitiveContains(XenonEdgeInfo.displayName)
    }

    private func foundXenonEdge(_ screen: NSScreen, method: String) {
        xeneonScreen = screen
        let frame = screen.frame
        statusMessage = "Found: \(screen.localizedName) (\(Int(frame.width))×\(Int(frame.height)))"
        logger.info("Xeneon Edge detected via \(method): \(screen.localizedName) at \(Int(frame.origin.x)),\(Int(frame.origin.y))")
    }

    // MARK: - Debug Info

    /// Returns info about all connected screens (for the settings UI).
    var allScreensInfo: [(name: String, resolution: String, isXenonEdge: Bool)] {
        NSScreen.screens.map { screen in
            let frame = screen.frame
            let resolution = "\(Int(frame.width))×\(Int(frame.height))"
            let isXeneon = isXenonEdgeByResolution(screen) || isXenonEdgeByName(screen)
            return (name: screen.localizedName, resolution: resolution, isXenonEdge: isXeneon)
        }
    }
}
