import Foundation

/// Shared serial queue for all AppleScript execution across the app.
///
/// NSAppleScript is **not** thread-safe — executing scripts concurrently from
/// different threads (even on separate NSAppleScript instances) can corrupt
/// the AppleScript runtime's internal state and cause `EXC_BAD_ACCESS` crashes.
///
/// Every bridge that uses NSAppleScript (SpotifyBridge, GoogleMeetBridge, etc.)
/// must route execution through this single serial queue.
nonisolated enum AppleScriptQueue {
    /// The one and only queue for AppleScript execution.
    static let shared = DispatchQueue(label: "com.ledge.AppleScriptQueue")
}
