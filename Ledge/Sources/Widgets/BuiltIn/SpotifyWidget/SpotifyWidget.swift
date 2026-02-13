import SwiftUI
import Combine

/// Spotify widget showing current playback with album art and controls.
///
/// Uses AppleScript to communicate with the Spotify desktop app locally.
/// No authentication required — just needs Spotify to be running.
struct SpotifyWidget {

    struct Config: Codable, Equatable {
        var showAlbumArt: Bool = true
        var showProgressBar: Bool = true
        var showAlbumColors: Bool = true
        var showSkipButtons: Bool = true
    }

    static let descriptor = WidgetDescriptor(
        typeID: "com.ledge.spotify",
        displayName: "Spotify",
        description: "Now playing with playback controls",
        iconSystemName: "music.note",
        minimumSize: .sixByTwo,
        defaultSize: .eightByFour,
        maximumSize: .twelveBySix,
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
    private let colorExtractor = AlbumColorExtractor()
    @State private var state = SpotifyBridge.PlaybackState()
    @State private var isSpotifyRunning = false
    @State private var albumColors: AlbumColorExtractor.Colors?
    @State private var lastArtworkURL = ""
    @State private var isSeeking = false
    @State private var seekPosition: Double = 0

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
            if state.isPlaying && !isSeeking {
                state.playerPosition += 1
            }
        }
        .onReceive(configStore.configDidChange) { changedID in
            if changedID == instanceID { loadConfig() }
        }
    }

    // MARK: - Now Playing (Size-Adaptive)

    private var nowPlayingView: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 280

            if isCompact {
                compactLayout(size: geometry.size)
            } else {
                fullLayout(size: geometry.size)
            }
        }
        .background(backgroundGradient)
        .onChange(of: state.artworkURL) { _, newURL in
            if !newURL.isEmpty && newURL != lastArtworkURL {
                lastArtworkURL = newURL
                extractColors(from: newURL)
            }
        }
    }

    // MARK: - Compact Layout (1 row)
    //
    // ┌──────────────────────────────────────────────────────────────┐
    // │ ┌────┐  Track Name           ══●═══  0:43 / 5:57           │
    // │ │Art │  Artist               ⏮ ◀10 ▶ 10▶ ⏭  🔊━━  ▫     │
    // │ └────┘                                                      │
    // └──────────────────────────────────────────────────────────────┘

    @ViewBuilder
    private func compactLayout(size: CGSize) -> some View {
        let artSize = size.height - 20

        HStack(spacing: 12) {
            // Album art
            if config.showAlbumArt, !state.artworkURL.isEmpty,
               let url = URL(string: state.artworkURL) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.3))
                        )
                }
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(state.trackName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(state.artistName)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)

                Text(state.albumName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            .frame(minWidth: 120, alignment: .leading)

            Spacer(minLength: 4)

            // Right side: progress + controls stacked
            VStack(spacing: 4) {
                // Progress bar
                if config.showProgressBar, state.trackDuration > 0 {
                    compactProgressBar(width: min(size.width * 0.35, 280))
                }

                // Controls
                compactControls
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func compactProgressBar(width: CGFloat) -> some View {
        VStack(spacing: 1) {
            GeometryReader { barGeo in
                let progress = isSeeking
                    ? min(seekPosition / state.trackDuration, 1.0)
                    : min(state.playerPosition / state.trackDuration, 1.0)
                let barWidth = barGeo.size.width

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(.white.opacity(0.2))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.green)
                        .frame(width: barWidth * progress, height: 5)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isSeeking = true
                            let fraction = max(0, min(value.location.x / barWidth, 1.0))
                            seekPosition = fraction * state.trackDuration
                        }
                        .onEnded { value in
                            let fraction = max(0, min(value.location.x / barWidth, 1.0))
                            bridge.setPosition(fraction * state.trackDuration)
                            state.playerPosition = fraction * state.trackDuration
                            isSeeking = false
                        }
                )
            }
            .frame(width: width, height: 12)

            HStack {
                Text(formatTime(isSeeking ? seekPosition : state.playerPosition))
                Spacer()
                Text(formatTime(state.trackDuration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.4))
            .frame(width: width)
        }
    }

    private var compactControls: some View {
        HStack(spacing: 14) {
            Button { bridge.previousTrack(); refreshAfterDelay() } label: {
                Image(systemName: "backward.fill").font(.system(size: 14))
            }
            if config.showSkipButtons {
                Button { bridge.skipBackward(10); refreshAfterDelay() } label: {
                    Image(systemName: "gobackward.10").font(.system(size: 13))
                }
            }
            Button { bridge.playPause(); refreshAfterDelay() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
            }
            if config.showSkipButtons {
                Button { bridge.skipForward(10); refreshAfterDelay() } label: {
                    Image(systemName: "goforward.10").font(.system(size: 13))
                }
            }
            Button { bridge.nextTrack(); refreshAfterDelay() } label: {
                Image(systemName: "forward.fill").font(.system(size: 14))
            }

            // Compact volume
            Image(systemName: volumeIcon)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
            Slider(
                value: Binding(
                    get: { Double(state.volume) },
                    set: { state.volume = Int($0); bridge.setVolume(Int($0)) }
                ),
                in: 0...100
            )
            .frame(width: 50)
            .tint(.green)
            .controlSize(.mini)

            Button { bridge.activateSpotify() } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    // MARK: - Full Layout (2+ rows)
    //
    // ┌─────────────────────────────────────────────────────────────┐
    // │ ┌──────────┐  Track Name (28pt)                            │
    // │ │          │  Artist (20pt)                                 │
    // │ │  Album   │  Album (16pt)                                 │
    // │ │   Art    │                                                │
    // │ │          │  ══════════●══════════  1:23 / 4:56           │
    // │ │          │  ⏮  ◀10  ▶  10▶  ⏭           🔊━━━  ▫      │
    // │ └──────────┘                                                │
    // └─────────────────────────────────────────────────────────────┘

    @ViewBuilder
    private func fullLayout(size: CGSize) -> some View {
        let artSize = size.height - 24

        HStack(spacing: 0) {
            // Album art — full height with padding
            if config.showAlbumArt, !state.artworkURL.isEmpty,
               let url = URL(string: state.artworkURL) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.3))
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

                // Track info - vertically centered
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.trackName)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(state.artistName)
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)

                    Text(state.albumName)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                // Progress bar
                if config.showProgressBar, state.trackDuration > 0 {
                    fullProgressBar
                }

                // Controls
                fullControlsRow
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Full Progress Bar

    private var fullProgressBar: some View {
        VStack(spacing: 3) {
            GeometryReader { barGeometry in
                let progress = isSeeking
                    ? min(seekPosition / state.trackDuration, 1.0)
                    : min(state.playerPosition / state.trackDuration, 1.0)
                let barWidth = barGeometry.size.width

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.2))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: barWidth * progress, height: 8)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isSeeking = true
                            let fraction = max(0, min(value.location.x / barWidth, 1.0))
                            seekPosition = fraction * state.trackDuration
                        }
                        .onEnded { value in
                            let fraction = max(0, min(value.location.x / barWidth, 1.0))
                            bridge.setPosition(fraction * state.trackDuration)
                            state.playerPosition = fraction * state.trackDuration
                            isSeeking = false
                        }
                )
            }
            .frame(height: 16)

            HStack {
                Text(formatTime(isSeeking ? seekPosition : state.playerPosition))
                Spacer()
                Text(formatTime(state.trackDuration))
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: - Full Controls

    private var fullControlsRow: some View {
        HStack(spacing: 0) {
            Spacer()

            HStack(spacing: 24) {
                Button { bridge.previousTrack(); refreshAfterDelay() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 20))
                }
                if config.showSkipButtons {
                    Button { bridge.skipBackward(10); refreshAfterDelay() } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 18))
                    }
                }
                Button { bridge.playPause(); refreshAfterDelay() } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32))
                }
                if config.showSkipButtons {
                    Button { bridge.skipForward(10); refreshAfterDelay() } label: {
                        Image(systemName: "goforward.10").font(.system(size: 18))
                    }
                }
                Button { bridge.nextTrack(); refreshAfterDelay() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 20))
                }
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 14)
                Slider(
                    value: Binding(
                        get: { Double(state.volume) },
                        set: { state.volume = Int($0); bridge.setVolume(Int($0)) }
                    ),
                    in: 0...100
                )
                .frame(width: 60)
                .tint(.green)
                .controlSize(.mini)

                Button { bridge.activateSpotify() } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Background Gradient

    private var backgroundGradient: some View {
        Group {
            if config.showAlbumColors, let colors = albumColors {
                LinearGradient(
                    colors: [colors.primary, colors.secondary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Color.clear
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

    private var volumeIcon: String {
        if state.volume == 0 { return "speaker.slash.fill" }
        if state.volume < 33 { return "speaker.wave.1.fill" }
        if state.volume < 66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    // MARK: - Helpers

    private func extractColors(from urlString: String) {
        let extractor = colorExtractor
        Task.detached {
            let colors = await extractor.extract(from: urlString)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.8)) {
                    albumColors = colors
                }
            }
        }
    }

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
            Toggle("Album art color background", isOn: $config.showAlbumColors)
            Toggle("Show skip 10s buttons", isOn: $config.showSkipButtons)
        }
        .onAppear { loadConfig() }
        .onChange(of: config) { _, _ in saveConfig() }
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
