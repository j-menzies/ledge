import SwiftUI

/// The root view displayed on the Xeneon Edge panel.
///
/// This view hosts the grid layout and renders all active widgets.
/// Observes ThemeManager directly so the dashboard updates live when
/// the user switches themes in Settings.
struct DashboardView: View {
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject var displayManager: DisplayManager
    let layoutManager: LayoutManager
    let configStore: WidgetConfigStore
    let registry: WidgetRegistry

    var body: some View {
        GridRenderer(
            layout: layoutManager.activeLayout,
            configStore: configStore,
            registry: registry
        )
        .environment(\.theme, themeManager.resolvedTheme)
        .ignoresSafeArea()
    }
}

// MARK: - Touch Debug Overlay

/// Debug overlay showing the touch pipeline state.
/// Displayed on the dashboard during development to diagnose touch issues.
struct TouchDebugOverlay: View {
    @EnvironmentObject var displayManager: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("AX Permission",
                value: displayManager.accessibilityPermission.rawValue,
                color: displayManager.accessibilityPermission == .granted ? .green : .yellow)

            row("Event Tap",
                value: displayManager.isTouchRemapperActive ? "Active" : "Inactive",
                color: displayManager.isTouchRemapperActive ? .green : .red)

            row("Calibration",
                value: displayManager.calibrationState.rawValue,
                color: (displayManager.calibrationState == .calibrated
                    || displayManager.calibrationState == .autoDetected) ? .green : .yellow)

            if let deviceID = displayManager.learnedDeviceID {
                row("Device ID", value: "\(deviceID)", color: .green)
            }

            if let touch = displayManager.lastTouchInfo {
                let orig = touch.originalPoint
                row("Last Touch",
                    value: String(format: "(%.0f, %.0f) → %@",
                                  orig.x, orig.y,
                                  touch.remappedPoint.map { String(format: "(%.0f, %.0f)", $0.x, $0.y) } ?? "nil"),
                    color: .white)
            }
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .padding(8)
        .background(.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func row(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label):")
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}
