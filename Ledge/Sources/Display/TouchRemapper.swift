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
///
/// This class is explicitly nonisolated because the CGEventTap callback runs on
/// the system's event tap thread and cannot be confined to MainActor.
nonisolated class TouchRemapper {

    private let logger = Logger(subsystem: "com.ledge.app", category: "TouchRemapper")

    /// The screen that the touchscreen should map to (the Xeneon Edge).
    private var targetScreen: NSScreen?

    /// The primary screen — macOS maps USB touchscreen absolute coordinates here.
    private var primaryScreen: NSScreen? {
        NSScreen.screens.first
    }

    /// Convert an NSScreen frame from Cocoa coordinates (origin bottom-left, Y up)
    /// to CG/Quartz coordinates (origin top-left of primary, Y down).
    /// CGEvent.location uses CG coordinates, so we must work in that space.
    private func cgRect(for screen: NSScreen) -> CGRect {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else {
            return screen.frame
        }
        let f = screen.frame
        return CGRect(
            x: f.origin.x,
            y: primaryHeight - f.origin.y - f.height,
            width: f.width,
            height: f.height
        )
    }

    /// The CGEventTap Mach port.
    /// `private(set)` because the callback function needs read access to re-enable the tap.
    private(set) var eventTap: CFMachPort?

    /// The run loop source for the event tap.
    private var runLoopSource: CFRunLoopSource?

    /// Whether the remapper is currently active.
    private(set) var isActive: Bool = false

    /// Known device IDs for the touchscreen. CGEvent field 87 may report any of these
    /// depending on which IOService node in the IOKit tree generates the event.
    private(set) var touchDeviceIDs: Set<Int64> = []

    /// Convenience accessor — returns a representative device ID (for display in UI).
    var touchDeviceID: Int64? {
        touchDeviceIDs.first
    }

    /// Whether we're in "learning mode" — waiting to identify the touchscreen device.
    private(set) var isLearning: Bool = false

    /// Callback invoked when learning completes.
    var onLearningComplete: (() -> Void)?

    /// Callback invoked when a touchscreen event is processed (for debug display).
    /// Parameters: device ID, original coordinates, remapped coordinates (nil if remapping failed).
    var onEventProcessed: ((_ deviceID: Int64, _ original: CGPoint, _ remapped: CGPoint?) -> Void)?

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

        // Log display geometry in CG coordinates (matching CGEvent.location)
        let sourceCG = cgRect(for: NSScreen.screens.first ?? targetScreen)
        let targetCG = cgRect(for: targetScreen)
        logger.info("Touch remapper started — targeting \(targetScreen.localizedName)")
        logger.info("  Source (primary CG): origin=(\(Int(sourceCG.origin.x)),\(Int(sourceCG.origin.y))) size=\(Int(sourceCG.width))×\(Int(sourceCG.height))")
        logger.info("  Target (edge CG):    origin=(\(Int(targetCG.origin.x)),\(Int(targetCG.origin.y))) size=\(Int(targetCG.width))×\(Int(targetCG.height))")
        for (i, screen) in NSScreen.screens.enumerated() {
            let cg = cgRect(for: screen)
            logger.info("  Screen \(i) CG: \(screen.localizedName) origin=(\(Int(cg.origin.x)),\(Int(cg.origin.y))) size=\(Int(cg.width))×\(Int(cg.height))")
        }
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
        touchDeviceIDs = []
        logger.info("Touch remapper learning mode — touch the Xeneon Edge screen")
    }

    /// Set a single touchscreen device ID (manual calibration / learning mode).
    func setTouchDeviceID(_ id: Int64) {
        touchDeviceIDs = [id]
        isLearning = false
        logger.info("Touch device ID set to \(id)")
    }

    /// Set multiple possible touchscreen device IDs (auto-detection via IOKit).
    /// CGEvent field 87 may report any of these depending on which IOService
    /// node in the IOKit tree generates the event.
    func setTouchDeviceIDs(_ ids: Set<Int64>) {
        touchDeviceIDs = ids
        isLearning = false
        logger.info("Touch device IDs set: \(ids.sorted())")
    }

    // MARK: - Coordinate Remapping

    /// Remap a point from primary display CG coordinates to the target display CG coordinates.
    ///
    /// macOS maps the USB touchscreen digitiser to the primary display's coordinate space.
    /// CGEvent.location uses CG/Quartz coordinates (origin top-left, Y down), but
    /// NSScreen.frame uses Cocoa coordinates (origin bottom-left, Y up). We convert
    /// all frames to CG space before normalising and remapping.
    func remapPoint(_ point: CGPoint) -> CGPoint? {
        guard let primary = primaryScreen,
              let target = targetScreen else {
            return nil
        }

        // Both source and target in CG coordinates (matching CGEvent.location)
        let sourceRect = cgRect(for: primary)
        let targetRect = cgRect(for: target)

        guard sourceRect.width > 0, sourceRect.height > 0 else {
            return nil
        }

        // Normalise the touch coordinates relative to the primary display (CG space)
        let normX = (point.x - sourceRect.origin.x) / sourceRect.width
        let normY = (point.y - sourceRect.origin.y) / sourceRect.height

        // Only remap if the normalised coordinates are in [0, 1]
        guard normX >= 0, normX <= 1, normY >= 0, normY <= 1 else {
            return nil
        }

        // Map to the target display in CG coordinates
        let remappedX = targetRect.origin.x + normX * targetRect.width
        let remappedY = targetRect.origin.y + normY * targetRect.height

        return CGPoint(x: remappedX, y: remappedY)
    }

    // MARK: - Event Processing

    /// Counter for throttling mouseMoved/mouseDragged logs.
    private var moveLogCounter: Int = 0

    /// Process a CGEvent and potentially remap its coordinates.
    /// Called from the C callback.
    func processEvent(_ event: CGEvent) -> CGEvent? {
        // mouseEventDeviceID (raw value 87) is not bridged to Swift's CGEventField enum
        let deviceID = event.getIntegerValueField(CGEventField(rawValue: 87)!)
        let eventType = event.type
        let location = event.location
        let typeName = Self.eventTypeName(eventType)

        // Determine if this is a "key" event worth full logging (not move/drag)
        let isKeyEvent = (eventType == .leftMouseDown || eventType == .leftMouseUp)

        // Learning mode: only capture device ID from mouseDown events.
        // This prevents trackpad movement (mouseMoved) from being misidentified
        // as the touchscreen. The user must physically tap the Xeneon Edge.
        if isLearning {
            if eventType == .leftMouseDown {
                touchDeviceIDs = [deviceID]
                isLearning = false
                logger.info("⚡ LEARN: captured device=\(deviceID) from \(typeName) at (\(Int(location.x)),\(Int(location.y)))")
                onLearningComplete?()
            } else if isKeyEvent {
                logger.info("⏳ LEARN: ignoring \(typeName) from device=\(deviceID) at (\(Int(location.x)),\(Int(location.y))) — waiting for mouseDown")
            }
            // During learning, pass ALL events through unmodified
            return event
        }

        // No device IDs known yet — pass through unmodified
        guard !touchDeviceIDs.isEmpty else {
            if isKeyEvent {
                logger.info("→ PASS: \(typeName) device=\(deviceID) at (\(Int(location.x)),\(Int(location.y))) — no device learned")
            }
            return event
        }

        // Not from the touchscreen — pass through unmodified
        guard touchDeviceIDs.contains(deviceID) else {
            if isKeyEvent {
                logger.info("→ PASS: \(typeName) device=\(deviceID) at (\(Int(location.x)),\(Int(location.y))) — not in touch device set")
            }
            return event
        }

        // ── This IS from the touchscreen device ──

        guard let remapped = remapPoint(location) else {
            // Coordinates are outside the primary display range. This happens when:
            // 1. A previous remapped mouseDown moved the cursor to the Edge, and
            //    subsequent drag/up events already carry Edge coordinates.
            // 2. macOS adjusted its absolute-to-screen mapping after our remap.
            // In both cases, the coordinates are already correct — pass through.
            let targetRect = targetScreen.map { cgRect(for: $0) }
            let isOnTarget = targetRect.map { $0.contains(location) } ?? false
            if isKeyEvent {
                if isOnTarget {
                    logger.info("→ THRU: \(typeName) device=\(deviceID) at (\(Int(location.x)),\(Int(location.y))) — already on Edge")
                } else {
                    logger.info("→ THRU: \(typeName) device=\(deviceID) at (\(Int(location.x)),\(Int(location.y))) — outside primary, passing through")
                }
            }
            onEventProcessed?(deviceID, location, location)
            return event
        }

        event.location = remapped
        if isKeyEvent {
            logger.info("✦ REMAP: \(typeName) device=\(deviceID) (\(Int(location.x)),\(Int(location.y))) → (\(Int(remapped.x)),\(Int(remapped.y)))")
        } else {
            moveLogCounter += 1
            if moveLogCounter % 60 == 1 {
                logger.info("✦ REMAP: \(typeName) device=\(deviceID) (\(Int(location.x)),\(Int(location.y))) → (\(Int(remapped.x)),\(Int(remapped.y))) [+\(self.moveLogCounter - 1) move events]")
            }
        }

        onEventProcessed?(deviceID, location, remapped)
        return event
    }

    /// Human-readable name for a CGEventType.
    private static func eventTypeName(_ type: CGEventType) -> String {
        switch type {
        case .leftMouseDown:    return "mouseDown"
        case .leftMouseUp:      return "mouseUp"
        case .leftMouseDragged: return "mouseDrag"
        case .mouseMoved:       return "mouseMove"
        default:                return "event(\(type.rawValue))"
        }
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
nonisolated private func touchRemapperCallback(
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

    // processEvent returned nil → drop the event (prevents cursor jumping to wrong location)
    return nil
}
