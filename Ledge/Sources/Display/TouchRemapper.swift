import AppKit
import CoreGraphics
import os.log

/// Remaps touch input from the Xeneon Edge touchscreen to the correct display coordinates.
///
/// macOS maps external touchscreen input to the primary display by default — there's
/// no built-in way to associate a USB touch digitiser with a specific secondary display.
/// This class uses a CGEventTap to intercept mouse events from the touchscreen and
/// transform the coordinates to the Xeneon Edge's position in the global display space.
///
/// Requires Accessibility permissions (System Settings > Privacy & Security > Accessibility).
class TouchRemapper {

    private let logger = Logger(subsystem: "com.ledge.app", category: "TouchRemapper")

    /// The screen that the touchscreen should map to (the Xeneon Edge).
    private var targetScreen: NSScreen?

    /// The primary screen (where macOS incorrectly maps touch input).
    private var primaryScreen: NSScreen? {
        NSScreen.screens.first
    }

    /// The CGEventTap Mach port.
    private var eventTap: CFMachPort?

    /// The run loop source for the event tap.
    private var runLoopSource: CFRunLoopSource?

    /// Whether the remapper is currently active.
    private(set) var isActive: Bool = false

    /// The device ID of the touchscreen, learned from the first touch.
    /// We use this to distinguish touchscreen events from regular mouse events.
    private var touchDeviceID: Int64?

    /// Whether we're in "learning mode" — waiting to identify the touchscreen device.
    private(set) var isLearning: Bool = false

    /// Callback invoked when learning completes.
    var onLearningComplete: (() -> Void)?

    // MARK: - Setup

    /// Start the touch remapper targeting the given screen.
    ///
    /// - Parameter screen: The NSScreen representing the Xeneon Edge.
    func start(targetScreen: NSScreen) {
        self.targetScreen = targetScreen

        guard checkAccessibilityPermissions() else {
            logger.error("Accessibility permissions not granted — cannot remap touch")
            return
        }

        // Create an event tap that intercepts mouse events
        let eventMask: CGEventMask = (
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue)
        )

        // Store self in a pointer so the C callback can access it
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: touchRemapperCallback,
            userInfo: userInfo
        ) else {
            logger.error("Failed to create CGEventTap — check Accessibility permissions")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true

        logger.info("Touch remapper started — targeting \(targetScreen.localizedName)")
    }

    /// Stop the touch remapper.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
        logger.info("Touch remapper stopped")
    }

    /// Enter "learning mode" — the next touch event on the primary display will be
    /// identified as the touchscreen device, and its device ID will be remembered.
    /// This lets us distinguish touchscreen events from trackpad/mouse events.
    func startLearning() {
        isLearning = true
        touchDeviceID = nil
        logger.info("Touch remapper learning mode — touch the Xeneon Edge screen")
    }

    /// Set the touchscreen device ID directly (if already known).
    func setTouchDeviceID(_ id: Int64) {
        touchDeviceID = id
        isLearning = false
        logger.info("Touch device ID set to \(id)")
    }

    // MARK: - Coordinate Remapping

    /// Remap a point from primary display coordinates to the target display coordinates.
    ///
    /// The touchscreen reports absolute coordinates that macOS maps to the primary display.
    /// We normalise those coordinates (0.0–1.0) and then map them to the target display.
    func remapPoint(_ point: CGPoint) -> CGPoint? {
        guard let primary = primaryScreen,
              let target = targetScreen else {
            return nil
        }

        let primaryFrame = primary.frame
        let targetFrame = target.frame

        // Normalise the touch coordinates relative to the primary display
        let normX = (point.x - primaryFrame.origin.x) / primaryFrame.width
        let normY = (point.y - primaryFrame.origin.y) / primaryFrame.height

        // Only remap if the normalised coordinates are in [0, 1]
        // (i.e., the original event was within the primary display bounds)
        guard normX >= 0, normX <= 1, normY >= 0, normY <= 1 else {
            return nil
        }

        // Map to the target display's coordinates in global display space
        let remappedX = targetFrame.origin.x + normX * targetFrame.width
        let remappedY = targetFrame.origin.y + normY * targetFrame.height

        return CGPoint(x: remappedX, y: remappedY)
    }

    // MARK: - Event Processing

    /// Process a CGEvent and potentially remap its coordinates.
    /// Called from the C callback.
    func processEvent(_ event: CGEvent) -> CGEvent? {
        let deviceID = event.getIntegerValueField(.mouseEventDeviceID)

        // Learning mode: capture the device ID from the first touch
        if isLearning {
            touchDeviceID = deviceID
            isLearning = false
            logger.info("Learned touch device ID: \(deviceID)")
            onLearningComplete?()
            // Still remap this event
        }

        // Only remap events from the touchscreen device
        if let knownDeviceID = touchDeviceID {
            guard deviceID == knownDeviceID else {
                // Not from the touchscreen — pass through unmodified
                return event
            }
        } else {
            // No device ID learned yet — pass through unmodified
            return event
        }

        // Remap the coordinates
        let originalLocation = event.location
        if let remapped = remapPoint(originalLocation) {
            event.location = remapped
        }

        return event
    }

    // MARK: - Permissions

    /// Check if Accessibility permissions are granted.
    func checkAccessibilityPermissions() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            logger.warning("Accessibility permissions not granted")
        }
        return trusted
    }

    /// Prompt the user to grant Accessibility permissions.
    func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - C Callback

/// The CGEventTap callback. Must be a plain C function (no captures).
/// Uses the userInfo pointer to access the TouchRemapper instance.
private func touchRemapperCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // Handle tap disabled events (system can temporarily disable taps under load)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Re-enable the tap
        if let userInfo {
            let remapper = Unmanaged<TouchRemapper>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = remapper.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let remapper = Unmanaged<TouchRemapper>.fromOpaque(userInfo).takeUnretainedValue()

    if let processed = remapper.processEvent(event) {
        return Unmanaged.passUnretained(processed)
    }

    return Unmanaged.passUnretained(event)
}
