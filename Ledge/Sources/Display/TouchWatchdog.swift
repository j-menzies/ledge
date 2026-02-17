import Foundation
import CoreGraphics
import os.log

/// Monitors CGEventTap health independently of the event callback.
///
/// The CGEventTap callback can only detect disables when events arrive. If the
/// tap is silently disabled and no events fire, the callback never runs and
/// we'd never know the tap is dead. This watchdog timer periodically checks
/// `CGEvent.tapIsEnabled()` and re-enables the tap if needed.
///
/// Runs on MainActor because it uses a `Timer` on the main run loop and
/// publishes state for the Touch Diagnostics widget to observe.
@MainActor
@Observable
final class TouchWatchdog {

    private let logger = Logger(subsystem: "com.ledge.app", category: "TouchWatchdog")

    // MARK: - Published State

    /// Whether the event tap is currently healthy (enabled).
    private(set) var isTapHealthy: Bool = true

    /// Number of times the tap has been found disabled since watchdog started.
    private(set) var disableCount: Int = 0

    /// Timestamp of the most recent tap disable detected by the watchdog.
    private(set) var lastDisableTime: Date? = nil

    /// Total number of health checks performed.
    private(set) var checksPerformed: Int = 0

    // MARK: - Internal

    /// The CGEventTap mach port to monitor.
    private var tap: CFMachPort?

    /// Timer that fires every `checkInterval` seconds.
    private var timer: Timer?

    /// How often to check tap health (seconds).
    private let checkInterval: TimeInterval = 5.0

    // MARK: - Lifecycle

    /// Start monitoring the given event tap.
    ///
    /// - Parameter tap: The `CFMachPort` returned by `CGEvent.tapCreate`.
    func start(tap: CFMachPort) {
        self.tap = tap
        disableCount = 0
        lastDisableTime = nil
        checksPerformed = 0
        isTapHealthy = true

        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkTapHealth()
            }
        }
        logger.info("Watchdog started — checking tap health every \(self.checkInterval)s")
    }

    /// Stop monitoring.
    func stop() {
        timer?.invalidate()
        timer = nil
        tap = nil
        logger.info("Watchdog stopped")
    }

    // MARK: - Health Check

    private func checkTapHealth() {
        guard let tap else { return }
        checksPerformed += 1

        let enabled = CGEvent.tapIsEnabled(tap: tap)
        if !enabled {
            // Tap was silently disabled — re-enable it
            CGEvent.tapEnable(tap: tap, enable: true)
            disableCount += 1
            lastDisableTime = Date()
            isTapHealthy = false
            logger.warning("⚠ Watchdog: event tap was disabled (detect #\(self.disableCount)) — re-enabled")

            // Verify re-enable worked
            let nowEnabled = CGEvent.tapIsEnabled(tap: tap)
            if nowEnabled {
                isTapHealthy = true
                logger.info("Watchdog: tap successfully re-enabled")
            } else {
                logger.error("Watchdog: tap re-enable FAILED — touch will not work until restart")
            }
        } else if !isTapHealthy {
            // Was previously unhealthy but now recovered
            isTapHealthy = true
        }
    }
}
