import SwiftUI
import Combine

/// Spotify widget showing current playback with album art and controls.
///
/// Uses AppleScript to communicate with the Spotify desktop app locally.
/// No authentication required — just needs Spotify to be running.
struct SpotifyWidget {

    struct Config: Codable {
        var showAlbumArt: Bool = true
        var showProgressBar: Bool = true
    }

    static let descriptor = WidgetDescriptor(
        typeID: "com.ledge.spotify",
        displayName: "Spotify",
        description: "Now playing with playback controls",
        iconSystemName: "music.note",
        minimumSize: .threeByTwo,
        defaultSize: .fourByTwo,
        maximumSize: .fiveByThree,
        defaultConfiguration: try? JSONEncoder().encode(Config()),
        viewFactory: { instanceID, configStore in
            AnyView(SpotifyWidgetView(instanceID: instanceID, configStore: configStore))
        },
        settingsFactory: { instanceID, configStore in
            AnyView(SpotifySettingsView(instanceID: instanceID, configStore: configStore))
        }
    )
}

// MARK: - View

struct SpotifyWidgetView: View {
    @Environment(\.theme) private var theme
    let instanceID: UUID
    let configStore: WidgetConfigStore

    @State private var config = SpotifyWidget.Config()
    private let bridge = SpotifyBridge()
    @State private var state = SpotifyBridge.PlaybackState()
    @State private var isSpotifyRunning = false

    private let pollTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let positionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !isSpotifyRunning {
                notRunningView
            } else if state.trackName.isEmpty {
                notPlayingView
            } else {
                nowPlayingView
            }
        }
        .onAppear {
            loadConfig()
            refreshState()
        }
        .onReceive(pollTimer) { _ in refreshState() }
        .onReceive(positionTimer) { _ in
            if state.isPlaying {
                state.playerPosition += 1
            }
        }
        .onReceive(configStore.configDidChange) { changedID in
            if changedID == instanceID { loadConfig() }
        }
    }

    // MARK: - Now Playing

    private var nowPlayingView: some View {
        GeometryReader { geometry in
            let artSize = min(geometry.size.height - 24, geometry.size.width * 0.4)

            HStack(spacing: 0) {
                // Prominent album art — fills left side
                if config.showAlbumArt, !state.artworkURL.isEmpty,
                   let url = URL(string: state.artworkURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(theme.primaryText.opacity(0.08))
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 32))
                                    .foregroundColor(theme.tertiaryText)
                            )
                    }
                    .frame(width: artSize, height: artSize)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.leading, 12)
                    .padding(.vertical, 12)
                }

                // Track info + controls
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    // Track name
                    Text(state.trackName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(theme.primaryText)
                        .lineLimit(2)

                    // Artist
                    Text(state.artistName)
                        .font(.system(size: 18))
                        .foregroundColor(theme.secondaryText)
                        .lineLimit(1)
                        .padding(.top, 3)

                    // Album
                    Text(state.albumName)
                        .font(.system(size: 15))
                        .foregroundColor(theme.tertiaryText)
                        .lineLimit(1)
                        .padding(.top, 2)

                    Spacer()

                    // Progress bar + controls centered together
                    if config.showProgressBar, state.trackDuration > 0 {
                        VStack(spacing: 4) {
                            GeometryReader { barGeometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2.5)
                                        .fill(theme.primaryText.opacity(0.15))
                                        .frame(height: 5)
                                    RoundedRectangle(cornerRadius: 2.5)
                                        .fill(Color.green)
                                        .frame(width: barGeometry.size.width * min(state.playerPosition / state.trackDuration, 1.0), height: 5)
                                }
                            }
                            .frame(height: 5)

                            HStack {
                                Text(formatTime(state.playerPosition))
                                Spacer()
                                Text(formatTime(state.trackDuration))
                            }
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(theme.tertiaryText)
                        }
                    }

                    // Controls row — centered under progress bar
                    HStack {
                        Spacer()

                        HStack(spacing: 28) {
                            Button { bridge.previousTrack(); refreshAfterDelay() } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 22))
                            }
                            Button { bridge.playPause(); refreshAfterDelay() } label: {
                                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 32))
                            }
                            Button { bridge.nextTrack(); refreshAfterDelay() } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 22))
                            }
                        }
                        .foregroundColor(theme.primaryText)
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .overlay(alignment: .trailing) {
                        // Open Spotify button — pinned to the right
                        Button {
                            bridge.activateSpotify()
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 18))
                                .foregroundColor(theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                        .help("Open Spotify")
                    }
                    .padding(.top, 6)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Placeholder States

    private var notRunningView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 32))
                .foregroundColor(theme.tertiaryText)
            Text("Spotify Not Running")
                .font(.system(size: 14))
                .foregroundColor(theme.tertiaryText)
            Button {
                bridge.activateSpotify()
            } label: {
                Text("Open Spotify")
                    .font(.system(size: 12))
                    .foregroundColor(theme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(theme.primaryText.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notPlayingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 32))
                .foregroundColor(theme.tertiaryText)
            Text("Not Playing")
                .font(.system(size: 14))
                .foregroundColor(theme.tertiaryText)
            Button {
                bridge.playPause()
                refreshAfterDelay()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 24))
                    .foregroundColor(theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func refreshAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            refreshState()
        }
    }

    private func refreshState() {
        let b = bridge
        Task.detached {
            let running = b.isSpotifyRunning()
            let newState = running ? b.fetchPlaybackState() : SpotifyBridge.PlaybackState()
            await MainActor.run {
                isSpotifyRunning = running
                state = newState
            }
        }
    }

    private func loadConfig() {
        if let saved: SpotifyWidget.Config = configStore.read(instanceID: instanceID, as: SpotifyWidget.Config.self) {
            config = saved
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Settings

struct SpotifySettingsView: View {
    let instanceID: UUID
    let configStore: WidgetConfigStore

    @State private var config = SpotifyWidget.Config()

    var body: some View {
        Form {
            Toggle("Show album art", isOn: $config.showAlbumArt)
            Toggle("Show progress bar", isOn: $config.showProgressBar)
        }
        .onAppear { loadConfig() }
        .onChange(of: config.showAlbumArt) { _, _ in saveConfig() }
        .onChange(of: config.showProgressBar) { _, _ in saveConfig() }
    }

    private func loadConfig() {
        if let saved: SpotifyWidget.Config = configStore.read(instanceID: instanceID, as: SpotifyWidget.Config.self) {
            config = saved
        }
    }

    private func saveConfig() {
        configStore.write(instanceID: instanceID, value: config)
    }
}
