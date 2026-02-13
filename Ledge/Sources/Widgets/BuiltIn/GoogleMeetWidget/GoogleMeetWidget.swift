import SwiftUI
import Combine

/// Google Meet widget with mic/camera controls and meeting status.
///
/// Uses AppleScript to communicate with Google Chrome. Requires the user
/// to grant Automation permission for Chrome on first use.
struct GoogleMeetWidget {

    static let descriptor = WidgetDescriptor(
        typeID: "com.ledge.google-meet",
        displayName: "Google Meet",
        description: "Control mic & camera in Google Meet",
        iconSystemName: "video",
        minimumSize: .threeByTwo,
        defaultSize: .fourByThree,
        maximumSize: .sixByFour,
        defaultConfiguration: nil,
        viewFactory: { instanceID, configStore in
            AnyView(GoogleMeetWidgetView(instanceID: instanceID, configStore: configStore))
        },
        settingsFactory: nil
    )
}

// MARK: - View

struct GoogleMeetWidgetView: View {
    @Environment(\.theme) private var theme
    let instanceID: UUID
    let configStore: WidgetConfigStore

    private let bridge = GoogleMeetBridge()
    @State private var meetState = GoogleMeetBridge.MeetState()

    private let pollTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 150

            if isCompact {
                compactLayout
            } else {
                fullLayout
            }
        }
        .onAppear { refreshState() }
        .onReceive(pollTimer) { _ in refreshState() }
    }

    // MARK: - Full Layout

    private var fullLayout: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "video")
                    .font(.system(size: 16))
                    .foregroundColor(meetState.inMeeting ? .green : theme.secondaryText)
                Text("Google Meet")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            if meetState.automationDenied {
                statusView(
                    icon: "lock.shield",
                    message: "Grant Chrome access",
                    detail: "System Settings > Privacy > Automation"
                )
            } else if meetState.jsDisabled {
                statusView(
                    icon: "applescript",
                    message: "Enable JavaScript in Chrome",
                    detail: "View > Developer > Allow JavaScript from Apple Events"
                )
            } else if !meetState.chromeRunning {
                statusView(icon: "globe", message: "Chrome not running")
            } else if !meetState.inMeeting {
                statusView(icon: "video.slash", message: "No active meeting")
            } else {
                meetingControls
            }
        }
    }

    private var meetingControls: some View {
        VStack(spacing: 0) {
            // Meeting title
            if !meetState.meetingTitle.isEmpty {
                Text(meetState.meetingTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }

            Spacer()

            // Mic and Camera controls
            HStack(spacing: 24) {
                controlButton(
                    icon: meetState.isMicMuted ? "mic.slash.fill" : "mic.fill",
                    label: meetState.isMicMuted ? "Unmute" : "Mute",
                    isActive: meetState.isMicMuted,
                    color: .red
                ) {
                    toggleMic()
                }

                controlButton(
                    icon: meetState.isCameraMuted ? "video.slash.fill" : "video.fill",
                    label: meetState.isCameraMuted ? "Cam Off" : "Cam On",
                    isActive: meetState.isCameraMuted,
                    color: .red
                ) {
                    toggleCamera()
                }
            }

            Spacer()
        }
    }

    // MARK: - Compact Layout

    private var compactLayout: some View {
        HStack(spacing: 12) {
            if meetState.automationDenied {
                Image(systemName: "lock.shield")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                Text("Grant Chrome access")
                    .font(.system(size: 14))
                    .foregroundColor(theme.tertiaryText)
                Spacer()
            } else if meetState.jsDisabled {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                Text("Enable JS in Chrome")
                    .font(.system(size: 14))
                    .foregroundColor(theme.tertiaryText)
                Spacer()
            } else if !meetState.chromeRunning || !meetState.inMeeting {
                Image(systemName: "video.slash")
                    .font(.system(size: 20))
                    .foregroundColor(theme.tertiaryText)
                Text(meetState.chromeRunning ? "No meeting" : "Chrome off")
                    .font(.system(size: 15))
                    .foregroundColor(theme.tertiaryText)
                Spacer()
            } else {
                // Meeting info
                VStack(alignment: .leading, spacing: 2) {
                    if !meetState.meetingTitle.isEmpty {
                        Text(meetState.meetingTitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(theme.primaryText)
                            .lineLimit(1)
                    }
                    Text("In meeting")
                        .font(.system(size: 13))
                        .foregroundColor(.green)
                }

                Spacer()

                // Compact mic/camera buttons
                HStack(spacing: 10) {
                    Button {
                        toggleMic()
                    } label: {
                        Image(systemName: meetState.isMicMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(meetState.isMicMuted ? .red : theme.secondaryText)
                            .frame(width: 36, height: 36)
                            .background(meetState.isMicMuted ? Color.red.opacity(0.15) : theme.primaryText.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        toggleCamera()
                    } label: {
                        Image(systemName: meetState.isCameraMuted ? "video.slash.fill" : "video.fill")
                            .font(.system(size: 20))
                            .foregroundColor(meetState.isCameraMuted ? .red : theme.secondaryText)
                            .frame(width: 36, height: 36)
                            .background(meetState.isCameraMuted ? Color.red.opacity(0.15) : theme.primaryText.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Components

    private func controlButton(icon: String, label: String, isActive: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(isActive ? color : theme.primaryText)
                    .frame(width: 56, height: 56)
                    .background(isActive ? color.opacity(0.15) : theme.primaryText.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? color : theme.tertiaryText)
            }
        }
        .buttonStyle(.plain)
    }

    private func statusView(icon: String, message: String, detail: String? = nil) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(theme.tertiaryText.opacity(0.5))
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(theme.tertiaryText)
            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(theme.tertiaryText.opacity(0.7))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var statusColor: Color {
        if meetState.automationDenied || meetState.jsDisabled { return .orange }
        if !meetState.chromeRunning { return .gray }
        if !meetState.inMeeting { return .orange }
        return .green
    }

    // MARK: - Actions

    private func refreshState() {
        let b = bridge
        Task.detached {
            let newState = b.getState()
            await MainActor.run {
                meetState = newState
            }
        }
    }

    private func toggleMic() {
        let b = bridge
        Task.detached {
            b.toggleMic()
            try? await Task.sleep(for: .milliseconds(500))
            let newState = b.getState()
            await MainActor.run {
                meetState = newState
            }
        }
    }

    private func toggleCamera() {
        let b = bridge
        Task.detached {
            b.toggleCamera()
            try? await Task.sleep(for: .milliseconds(500))
            let newState = b.getState()
            await MainActor.run {
                meetState = newState
            }
        }
    }
}
