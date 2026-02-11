import SwiftUI

/// Settings window displayed on the primary monitor.
///
/// This is where the user configures Ledge — display selection, layout editing,
/// widget management, etc. It's a standard SwiftUI window (not a non-activating panel)
/// because settings interaction needs full keyboard/mouse focus.
struct SettingsView: View {
    @EnvironmentObject var displayManager: DisplayManager

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink(destination: DisplaySettingsView()) {
                    Label("Display", systemImage: "display")
                }
                NavigationLink(destination: WidgetSettingsView()) {
                    Label("Widgets", systemImage: "square.grid.2x2")
                }
                NavigationLink(destination: LayoutSettingsView()) {
                    Label("Layout", systemImage: "rectangle.3.group")
                }
                NavigationLink(destination: AboutView()) {
                    Label("About", systemImage: "info.circle")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Ledge")
        } detail: {
            DisplaySettingsView()
        }
    }
}

// MARK: - Display Settings

struct DisplaySettingsView: View {
    @EnvironmentObject var displayManager: DisplayManager

    var body: some View {
        Form {
            Section("Xeneon Edge") {
                HStack {
                    Image(systemName: displayManager.isActive ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(displayManager.isActive ? .green : .red)
                    Text(displayManager.statusMessage)
                }

                if !displayManager.isActive, displayManager.xeneonScreen != nil {
                    Button("Show Panel") {
                        displayManager.showPanel()
                    }
                } else if displayManager.isActive {
                    Button("Hide Panel") {
                        displayManager.hidePanel()
                    }
                }

                Button("Re-scan Displays") {
                    displayManager.detectXenonEdge()
                }
            }

            Section("Touch Remapping") {
                HStack {
                    Image(systemName: displayManager.isTouchRemapperActive ? "hand.tap.fill" : "hand.tap")
                        .foregroundColor(displayManager.isTouchRemapperActive ? .green : .secondary)
                    Text(displayManager.touchStatus)
                }

                Text("macOS maps the Xeneon Edge touchscreen to the primary display. The touch remapper intercepts and redirects touch input to the correct screen.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !displayManager.isTouchRemapperActive {
                    Button("Enable Touch Remapping") {
                        displayManager.startTouchRemapper()
                    }
                    .disabled(displayManager.xeneonScreen == nil)
                } else {
                    Button("Calibrate Touch") {
                        displayManager.calibrateTouch()
                    }
                    .help("Touch the Xeneon Edge screen to identify the touchscreen device")

                    Button("Disable Touch Remapping") {
                        displayManager.stopTouchRemapper()
                    }
                }
            }

            Section("Connected Displays") {
                ForEach(Array(displayManager.allScreensInfo.enumerated()), id: \.offset) { index, info in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(info.name)
                                .font(.headline)
                            Text(info.resolution)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if info.isXenonEdge {
                            Text("Xeneon Edge")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display")
    }
}

// MARK: - Placeholder Views

struct WidgetSettingsView: View {
    var body: some View {
        VStack {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Widget settings coming in Phase 1")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Widgets")
    }
}

struct LayoutSettingsView: View {
    var body: some View {
        VStack {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Layout editor coming in Phase 1")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Layout")
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Ledge")
                .font(.largeTitle)
            Text("A macOS widget dashboard for the Corsair Xeneon Edge")
                .foregroundColor(.secondary)
            Text("Phase 0 — Foundation")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}

#Preview {
    SettingsView()
        .environmentObject(DisplayManager())
        .frame(width: 600, height: 400)
}
