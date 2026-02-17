import AppKit
import SwiftUI
import Combine
import AVFoundation
import CoreLocation
import EventKit
import os.log

/// Marker subclass for the fullscreen helper window.
/// Used to exclude it from window enumeration in AppDelegate.
class FullscreenHelperWindow: NSWindow {}

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

    /// Whether the panel is waiting for widget permissions before rendering.
    @Published private(set) var permissionGateActive: Bool = false

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

    /// IOKit HID-based touchscreen detector — identifies the device without manual calibration.
    private let hidDetector = HIDTouchDetector()

    /// Flight recorder capturing recent touch events for diagnostics.
    let flightRecorder = TouchFlightRecorder()

    /// Watchdog timer that monitors CGEventTap health independently of the callback.
    let touchWatchdog = TouchWatchdog()

    /// Whether Accessibility permissions have been granted (required for CGEventTap).
    @Published private(set) var accessibilityPermission: AccessibilityPermission = .unknown

    /// Whether the touch remapper event tap is active.
    @Published private(set) var isTouchRemapperActive: Bool = false

    /// Whether the touchscreen device has been identified via calibration.
    @Published private(set) var calibrationState: CalibrationState = .notStarted

    /// The learned HID device ID for the touchscreen (nil until calibrated).
    @Published private(set) var learnedDeviceID: Int64? = nil

    /// Info about the most recent touch event (for debug overlay).
    @Published private(set) var lastTouchInfo: TouchEventInfo? = nil

    /// Derived status string for the settings UI.
    var touchStatus: String {
        switch accessibilityPermission {
        case .unknown:
            return "Not started"
        case .waiting:
            return "Waiting for Accessibility permission..."
        case .granted:
            if !isTouchRemapperActive {
                return "Event tap failed to start"
            }
            switch calibrationState {
            case .notStarted:
                return "Active — waiting for calibration"
            case .learning:
                return "Calibrating — touch the Xeneon Edge screen..."
            case .calibrated:
                if let id = learnedDeviceID {
                    return "Active — device \(id)"
                }
                return "Active — calibrated"
            case .autoDetected:
                if let id = learnedDeviceID {
                    return "Active — auto-detected device \(id)"
                }
                return "Active — auto-detected"
            }
        }
    }

    // MARK: - Touch Types

    enum AccessibilityPermission: String {
        case unknown = "Unknown"
        case waiting = "Waiting for grant..."
        case granted = "Granted"
    }

    enum CalibrationState: String {
        case notStarted = "Not started"
        case learning = "Touch the Xeneon Edge..."
        case calibrated = "Calibrated"
        case autoDetected = "Auto-detected"
    }

    struct TouchEventInfo {
        let deviceID: Int64
        let originalPoint: CGPoint
        let remappedPoint: CGPoint?
        let timestamp: Date
    }

    // MARK: - Display Security

    /// Whether the panel is currently blanked due to screen lock, sleep, or screensaver.
    @Published private(set) var isDisplayBlanked: Bool = false

    // MARK: - Private

    private let logger = Logger(subsystem: "com.ledge.app", category: "DisplayManager")
    private var displayReconfigurationToken: Any?
    private var permissionPollTimer: Timer?
    private var appActivationObserver: Any?
    /// A helper window that enters macOS native fullscreen on the Edge display.
    /// This creates a fullscreen Space which auto-hides the menu bar per-display.
    /// The LedgePanel (with .fullScreenAuxiliary) renders on top of it.
    private var fullscreenHelper: FullscreenHelperWindow?
    /// Observer for fullscreen entry to show the panel once the Space is ready.
    private var fullscreenObserver: Any?
    /// Permission gate: timer, retained objects, and completion for pre-panel permission requests.
    private var permissionGateTimer: Timer?
    private var gateLocationManager: CLLocationManager?
    private var gateEventStore: EKEventStore?
    private var gatedPermissions: Set<WidgetPermission> = []
    private var onPermissionsResolved: (() -> Void)?
    /// Observers for sleep/lock/screensaver events.
    private var securityObservers: [Any] = []

    // MARK: - Lifecycle

    init() {
        registerForDisplayChanges()
        registerForSecurityEvents()
        detectXenonEdge()
    }

    deinit {
        for observer in securityObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
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
            touchRemapper.panel = panel
            logger.info("Created LedgePanel on Xeneon Edge")
        }

        // The LedgePanel at .screenSaver level (1000) is well above the menu bar (~24),
        // so it covers the menu bar on the Edge without needing a fullscreen helper.
        //
        // We deliberately avoid a FullscreenHelperWindow because entering native fullscreen
        // on the Edge creates a dedicated fullscreen Space that participates in macOS Space
        // switching — when the user swipes Spaces on their primary display, the Edge Space
        // would animate/switch too, disrupting the always-visible widget dashboard.
        revealPanel(on: screen)
    }

    /// Actually make the panel visible. Called directly (no fullscreen helper needed)
    /// or after the fullscreen helper finishes its transition.
    private func revealPanel(on screen: NSScreen) {
        // Use orderFrontRegardless + makeKey separately instead of makeKeyAndOrderFront.
        // makeKeyAndOrderFront can trigger app activation even on .nonactivatingPanel.
        // orderFrontRegardless brings the panel forward without activating the app.
        NSApp.preventWindowOrdering()
        panel?.orderFrontRegardless()
        panel?.makeKey()
        isActive = true
        statusMessage = "Active on \(screen.localizedName)"
        logger.info("Panel is now visible on Xeneon Edge")
    }

    /// Hide the panel (but keep the screen reference).
    func hidePanel() {
        panel?.orderOut(nil)
        isActive = false
        tearDownFullscreenHelper()
        statusMessage = "Panel hidden (Xeneon Edge still connected)"
        logger.info("Panel hidden")
    }

    /// Completely tear down the panel.
    func destroyPanel() {
        panel?.orderOut(nil)
        touchRemapper.panel = nil
        panel = nil
        isActive = false
        tearDownFullscreenHelper()
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
                // Screen changed (e.g., rearranged) — reposition panel AND update touch remapper
                logger.info("Xeneon Edge repositioned, updating panel frame and touch target")
                panel?.reposition(on: currentScreen)
                touchRemapper.updateTargetScreen(currentScreen)
            }
        } else if previousScreen != nil {
            // Xeneon Edge was disconnected
            logger.info("Xeneon Edge disconnected")
            destroyPanel()
            statusMessage = "Xeneon Edge disconnected. Waiting for reconnection..."
        }
    }

    // MARK: - Touch Remapper Management

    /// Start the touch remapper. Requests Accessibility permissions if needed
    /// and polls until granted, then automatically starts the event tap and calibration.
    func startTouchRemapper() {
        guard xeneonScreen != nil else {
            accessibilityPermission = .unknown
            logger.warning("Cannot start touch remapper: Xeneon Edge not detected")
            return
        }

        if !touchRemapper.checkAccessibilityPermissions() {
            touchRemapper.requestAccessibilityPermissions()
            accessibilityPermission = .waiting
            beginPermissionPolling()
            logger.info("Accessibility permission requested — polling for grant")
            return
        }

        accessibilityPermission = .granted
        proceedWithTouchRemapper()
    }

    /// Stop the touch remapper and reset all touch state.
    func stopTouchRemapper() {
        touchRemapper.stop()
        touchWatchdog.stop()
        tearDownPermissionPolling()
        isTouchRemapperActive = false
        calibrationState = .notStarted
        learnedDeviceID = nil
        lastTouchInfo = nil
        logger.info("Touch remapper stopped")
    }

    /// Start calibration — the next touch event identifies the touchscreen device.
    func calibrateTouch() {
        guard touchRemapper.isActive else {
            logger.warning("Cannot calibrate: touch remapper not active")
            return
        }

        touchRemapper.startLearning()
        calibrationState = .learning

        touchRemapper.onLearningComplete = { [weak self] in
            Task { @MainActor in
                self?.calibrationState = .calibrated
                self?.learnedDeviceID = self?.touchRemapper.touchDeviceID
                self?.logger.info("Touch calibration complete — device ID: \(self?.touchRemapper.touchDeviceID ?? -1)")
            }
        }
    }

    // MARK: - Permission Polling

    /// Called once Accessibility permission is confirmed granted.
    private func proceedWithTouchRemapper() {
        guard let screen = xeneonScreen else { return }

        // Auto-detect the touchscreen device via IOKit HID.
        // This identifies the exact USB touch controller by VID/PID, eliminating
        // the need for manual calibration (which was unreliable — it often
        // captured the mouse instead of the touchscreen).
        if let result = hidDetector.detect() {
            touchRemapper.setTouchDeviceIDs(result.allDeviceIDs)
            calibrationState = .autoDetected
            learnedDeviceID = result.allDeviceIDs.sorted().last  // show highest ID in UI (likely the event driver)
            logger.info("Auto-detected touchscreen: \(result.product ?? "unknown") (\(result.allDeviceIDs.count) possible IDs)")
        } else {
            logger.warning("Could not auto-detect touchscreen — manual calibration available via Settings")
            calibrationState = .notStarted
        }

        // Wire up the diagnostics event callback — feeds both lastTouchInfo (UI) and flight recorder
        touchRemapper.onEventProcessed = { [weak self] deviceID, original, remapped, eventTypeRaw, delivered, seqID, arrivalTime in
            // Record in flight recorder (thread-safe, fast)
            let entry = TouchFlightRecorder.Entry(
                timestamp: arrivalTime,
                sequenceID: seqID,
                deviceID: deviceID,
                originalPoint: original,
                remappedPoint: remapped,
                eventType: .init(cgEventType: eventTypeRaw),
                deliveryStatus: delivered ? .delivered : .dropped,
                deliveryLatencyMs: nil  // Updated by panel delivery confirmation
            )
            self?.flightRecorder.append(entry)

            // Update UI state on MainActor
            Task { @MainActor in
                self?.lastTouchInfo = TouchEventInfo(
                    deviceID: deviceID,
                    originalPoint: original,
                    remappedPoint: remapped,
                    timestamp: arrivalTime
                )
            }
        }

        touchRemapper.start(targetScreen: screen)
        isTouchRemapperActive = touchRemapper.isActive

        // Start the watchdog to monitor event tap health
        if let tap = touchRemapper.eventTap {
            touchWatchdog.start(tap: tap)
        }

        if touchRemapper.isActive {
            if calibrationState == .autoDetected {
                logger.info("Event tap active — touchscreen auto-detected, ready for input")
            } else {
                logger.info("Event tap active — use Settings to calibrate touch device")
            }
        } else {
            logger.error("Event tap failed to start")
        }
    }

    /// Start polling for Accessibility permission grant (timer + app activation observer).
    private func beginPermissionPolling() {
        tearDownPermissionPolling()

        // Poll every 2 seconds
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndProceedIfPermitted()
            }
        }

        // Also check when the user switches back to Ledge (common flow: grant in System Settings → switch back)
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in
                self?.checkAndProceedIfPermitted()
            }
        }
    }

    /// Check if permission was granted and proceed if so.
    private func checkAndProceedIfPermitted() {
        guard accessibilityPermission == .waiting else {
            tearDownPermissionPolling()
            return
        }

        if touchRemapper.checkAccessibilityPermissions() {
            logger.info("Accessibility permission granted")
            accessibilityPermission = .granted
            tearDownPermissionPolling()
            proceedWithTouchRemapper()
        }
    }

    /// Clean up permission polling resources.
    private func tearDownPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil

        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
    }

    // MARK: - Widget Permission Gate
    //
    // Before showing the panel, check if active widgets need permissions that
    // would trigger system dialogs (camera, location, calendar). Request them
    // upfront so dialogs are dismissed before the fullscreen transition starts.

    /// Show the panel only after all required widget permissions are resolved.
    ///
    /// "Resolved" means the user has responded to the dialog (granted or denied).
    /// We don't block on denied — the widget degrades gracefully. We only wait
    /// for `.notDetermined` permissions that would produce a system dialog.
    func showPanelWhenReady(requiredPermissions: Set<WidgetPermission>, then completion: @escaping () -> Void) {
        guard xeneonScreen != nil else {
            logger.error("Cannot show panel: no Xeneon Edge screen detected")
            return
        }

        // Filter to permissions the user hasn't responded to yet
        let unresolved = requiredPermissions.filter { !isPermissionResolved($0) }

        if unresolved.isEmpty {
            logger.info("All widget permissions resolved — proceeding with panel")
            permissionGateActive = false
            showPanel()
            completion()
        } else {
            logger.info("Waiting for \(unresolved.count) permission(s): \(unresolved.map(\.rawValue).joined(separator: ", "))")
            permissionGateActive = true
            gatedPermissions = unresolved
            statusMessage = "Waiting for permissions..."
            onPermissionsResolved = { [weak self] in
                self?.permissionGateActive = false
                self?.showPanel()
                completion()
            }

            // Request each unresolved permission (triggers system dialogs)
            for perm in unresolved {
                requestPermission(perm)
            }

            // Poll until all dialogs are dismissed
            beginPermissionGatePolling()
        }
    }

    /// Check if a permission has been resolved (user responded — granted or denied).
    private func isPermissionResolved(_ permission: WidgetPermission) -> Bool {
        switch permission {
        case .camera:
            return AVCaptureDevice.authorizationStatus(for: .video) != .notDetermined
        case .location:
            return CLLocationManager().authorizationStatus != .notDetermined
        case .calendar:
            return EKEventStore.authorizationStatus(for: .event) != .notDetermined
        }
    }

    /// Request a specific permission (shows system dialog if not determined).
    private func requestPermission(_ permission: WidgetPermission) {
        switch permission {
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        case .location:
            if gateLocationManager == nil {
                gateLocationManager = CLLocationManager()
            }
            gateLocationManager?.requestWhenInUseAuthorization()
        case .calendar:
            if gateEventStore == nil {
                gateEventStore = EKEventStore()
            }
            gateEventStore?.requestFullAccessToEvents { _, _ in }
        }
    }

    private func beginPermissionGatePolling() {
        permissionGateTimer?.invalidate()
        permissionGateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermissionGate()
            }
        }
    }

    private func checkPermissionGate() {
        let stillUnresolved = gatedPermissions.filter { !isPermissionResolved($0) }

        if stillUnresolved.isEmpty {
            logger.info("All widget permissions resolved — showing panel")
            permissionGateTimer?.invalidate()
            permissionGateTimer = nil
            gateLocationManager = nil
            gateEventStore = nil
            gatedPermissions = []
            onPermissionsResolved?()
            onPermissionsResolved = nil
        }
    }

    // MARK: - Fullscreen Helper (Menu Bar Hiding)

    /// Create a helper window that enters native macOS fullscreen on the Edge display.
    ///
    /// When a window goes fullscreen on a secondary display, macOS creates a dedicated
    /// fullscreen Space for that display and auto-hides the menu bar. This is the same
    /// mechanism used by Safari, Chrome, etc. when you click "Full Screen > Entire Screen".
    ///
    /// The LedgePanel (with `.fullScreenAuxiliary` + `.canJoinAllSpaces`) renders on top
    /// of the fullscreen helper, receiving all touch/mouse input as before.
    private func ensureFullscreenHelper(on screen: NSScreen, completion: @escaping () -> Void) {
        // If helper already exists and is in fullscreen, proceed immediately
        if let helper = fullscreenHelper, helper.styleMask.contains(.fullScreen) {
            completion()
            return
        }

        // If helper exists but mid-transition, wait for it
        if fullscreenHelper != nil {
            observeFullscreenEntry(completion: completion)
            return
        }

        // The helper needs .titled for toggleFullScreen to work. fullSizeContentView +
        // transparent titlebar makes the titlebar invisible. The window is entirely black
        // and serves only to create the fullscreen Space.
        let helper = FullscreenHelperWindow(
            contentRect: screen.frame,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        helper.titleVisibility = .hidden
        helper.titlebarAppearsTransparent = true
        helper.backgroundColor = .black
        helper.isReleasedWhenClosed = false
        helper.hasShadow = false
        helper.collectionBehavior = [.fullScreenPrimary]
        helper.setFrame(screen.frame, display: false)

        fullscreenHelper = helper

        // Observe fullscreen entry BEFORE triggering the transition
        observeFullscreenEntry(completion: completion)

        // Show and enter fullscreen.
        // Use orderFrontRegardless instead of orderFront to avoid activating the app.
        NSApp.preventWindowOrdering()
        helper.orderFrontRegardless()
        helper.toggleFullScreen(nil)

        logger.info("Fullscreen helper created — entering fullscreen on \(screen.localizedName)")
    }

    /// Wait for the fullscreen helper to finish entering fullscreen, then call completion.
    private func observeFullscreenEntry(completion: @escaping () -> Void) {
        // Clean up any previous observer
        if let obs = fullscreenObserver {
            NotificationCenter.default.removeObserver(obs)
            fullscreenObserver = nil
        }

        fullscreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: fullscreenHelper,
            queue: .main
        ) { [weak self] _ in
            if let obs = self?.fullscreenObserver {
                NotificationCenter.default.removeObserver(obs)
                self?.fullscreenObserver = nil
            }
            completion()
        }

        // Fallback: if the notification never fires, show after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard self?.fullscreenObserver != nil else { return }
            if let obs = self?.fullscreenObserver {
                NotificationCenter.default.removeObserver(obs)
                self?.fullscreenObserver = nil
            }
            self?.logger.warning("Fullscreen entry timed out — showing panel anyway")
            completion()
        }
    }

    /// Exit fullscreen and clean up the helper window.
    private func tearDownFullscreenHelper() {
        if let observer = fullscreenObserver {
            NotificationCenter.default.removeObserver(observer)
            fullscreenObserver = nil
        }
        guard let helper = fullscreenHelper else { return }
        if helper.styleMask.contains(.fullScreen) {
            helper.toggleFullScreen(nil)
        }
        helper.orderOut(nil)
        fullscreenHelper = nil
        logger.info("Fullscreen helper torn down")
    }

    // MARK: - Display Security (Sleep / Lock / Screensaver)
    //
    // The Xeneon Edge must not leak widget content when the system is locked,
    // sleeping, or showing the screensaver. We observe all relevant system
    // notifications and blank the panel until the user unlocks/wakes.

    /// Register for all system events that should cause the panel to blank.
    private func registerForSecurityEvents() {
        let ws = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()

        // Display sleep/wake
        securityObservers.append(
            ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.blankDisplay(reason: "displays slept") }
            }
        )
        securityObservers.append(
            ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.unblankDisplay(reason: "displays woke") }
            }
        )

        // System sleep/wake (covers lid close, sleep menu, idle sleep)
        securityObservers.append(
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.blankDisplay(reason: "system sleeping") }
            }
        )
        securityObservers.append(
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                // Don't unblank on wake — wait for unlock. If no lock screen is configured,
                // screensDidWake will handle it.
            }
        )

        // Screen lock/unlock (requires login to dismiss)
        securityObservers.append(
            dc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.blankDisplay(reason: "screen locked") }
            }
        )
        securityObservers.append(
            dc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.unblankDisplay(reason: "screen unlocked") }
            }
        )

        // Screensaver start/stop
        securityObservers.append(
            dc.addObserver(forName: NSNotification.Name("com.apple.screensaver.didStart"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.blankDisplay(reason: "screensaver started") }
            }
        )
        securityObservers.append(
            dc.addObserver(forName: NSNotification.Name("com.apple.screensaver.didStop"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.unblankDisplay(reason: "screensaver stopped") }
            }
        )

        logger.info("Registered for sleep/lock/screensaver security events")
    }

    /// Hide panel content — shows black to prevent information leakage.
    private func blankDisplay(reason: String) {
        guard !isDisplayBlanked else { return }
        isDisplayBlanked = true
        panel?.contentView?.isHidden = true
        logger.info("Display blanked: \(reason)")
    }

    /// Restore panel content after the system is unlocked/awake.
    private func unblankDisplay(reason: String) {
        guard isDisplayBlanked else { return }
        isDisplayBlanked = false
        panel?.contentView?.isHidden = false
        logger.info("Display unblanked: \(reason)")
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
