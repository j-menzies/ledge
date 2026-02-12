import Foundation
import os.log

/// Bridge to Spotify via AppleScript for local playback control.
///
/// Uses AppleScript to query Spotify state and control playback without
/// requiring any authentication or API keys.
///
/// Must be `nonisolated` — NSAppleScript blocks the calling thread, and the
/// project default actor isolation is MainActor. Callers should dispatch
/// from a background context (`Task.detached` or an actor).
nonisolated class SpotifyBridge: @unchecked Sendable {

    private nonisolated(unsafe) let logger = Logger(subsystem: "com.ledge.app", category: "SpotifyBridge")

    struct PlaybackState: Sendable {
        var isPlaying: Bool = false
        var trackName: String = ""
        var artistName: String = ""
        var albumName: String = ""
        var artworkURL: String = ""
        var trackDuration: Double = 0  // seconds
        var playerPosition: Double = 0  // seconds
    }

    /// Whether Spotify is currently running.
    func isSpotifyRunning() -> Bool {
        let script = """
        tell application "System Events"
            return (name of processes) contains "Spotify"
        end tell
        """
        return runAppleScript(script) == "true"
    }

    /// Fetch current playback state.
    func fetchPlaybackState() -> PlaybackState {
        let script = """
        tell application "Spotify"
            if player state is playing then
                set isPlaying to "true"
            else
                set isPlaying to "false"
            end if
            try
                set trackName to name of current track
                set artistName to artist of current track
                set albumName to album of current track
                set artURL to artwork url of current track
                set trackDur to (duration of current track) / 1000
                set playerPos to player position
                return isPlaying & "|||" & trackName & "|||" & artistName & "|||" & albumName & "|||" & artURL & "|||" & (trackDur as text) & "|||" & (playerPos as text)
            on error
                return isPlaying & "|||" & "" & "|||" & "" & "|||" & "" & "|||" & "" & "|||" & "0" & "|||" & "0"
            end try
        end tell
        """

        guard let result = runAppleScript(script) else { return PlaybackState() }

        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 7 else { return PlaybackState() }

        return PlaybackState(
            isPlaying: parts[0] == "true",
            trackName: parts[1],
            artistName: parts[2],
            albumName: parts[3],
            artworkURL: parts[4],
            trackDuration: Double(parts[5]) ?? 0,
            playerPosition: Double(parts[6]) ?? 0
        )
    }

    /// Play/pause toggle.
    func playPause() {
        runAppleScriptFire("tell application \"Spotify\" to playpause")
    }

    /// Skip to next track.
    func nextTrack() {
        runAppleScriptFire("tell application \"Spotify\" to next track")
    }

    /// Skip to previous track.
    func previousTrack() {
        runAppleScriptFire("tell application \"Spotify\" to previous track")
    }

    /// Bring Spotify to the foreground.
    func activateSpotify() {
        runAppleScriptFire("tell application \"Spotify\" to activate")
    }

    // MARK: - Private

    @discardableResult
    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            logger.debug("AppleScript error: \(error)")
            return nil
        }
        return result.stringValue
    }

    /// Fire-and-forget AppleScript on a background thread.
    private func runAppleScriptFire(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { return }
            script.executeAndReturnError(&error)
        }
    }
}
