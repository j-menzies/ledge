import SwiftUI

/// The root view displayed on the Xeneon Edge panel.
///
/// This view hosts the grid layout and renders all active widgets.
/// Observes ThemeManager directly so the dashboard updates live when
/// the user switches themes in Settings.
///
/// Supports swipe gestures to switch between saved layouts (pages)
/// and displays a subtle page indicator when multiple pages exist.
struct DashboardView: View {
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject var displayManager: DisplayManager
    let layoutManager: LayoutManager
    let configStore: WidgetConfigStore
    let registry: WidgetRegistry

    /// Tracks the horizontal drag distance for swipe gesture.
    @State private var dragOffset: CGFloat = 0
    /// Briefly shows the page indicator after a page switch.
    @State private var showPageIndicator = false

    var body: some View {
        ZStack(alignment: .bottom) {
            GridRenderer(
                layout: layoutManager.activeLayout,
                configStore: configStore,
                registry: registry
            )
            .offset(x: dragOffset)
            .gesture(swipeGesture)

            // Page indicator (only shown when multiple pages exist)
            if layoutManager.pageCount > 1 {
                PageIndicator(
                    pageCount: layoutManager.pageCount,
                    activeIndex: layoutManager.activePageIndex
                )
                .opacity(showPageIndicator ? 1.0 : 0.3)
                .padding(.bottom, 4)
                .animation(.easeInOut(duration: 0.3), value: showPageIndicator)
            }
        }
        .environment(\.theme, themeManager.resolvedTheme)
        .ignoresSafeArea()
        .onChange(of: layoutManager.activeLayout.id) { _, _ in
            flashPageIndicator()
        }
        // Keep panel transparency in sync with the widget background style.
        // When Blur or Transparent, the panel must be non-opaque so the desktop
        // wallpaper (or background image) shows through gaps between widgets.
        .onChange(of: themeManager.widgetBackgroundStyle) { _, newStyle in
            displayManager.panel?.setTransparent(newStyle != .solid)
        }
        .onChange(of: themeManager.dashboardBackgroundMode) { _, _ in
            displayManager.panel?.setTransparent(themeManager.widgetBackgroundStyle != .solid)
        }
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onChanged { value in
                // Only respond to horizontal drags
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragOffset = value.translation.width * 0.3  // dampened drag
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                withAnimation(.easeOut(duration: 0.25)) {
                    dragOffset = 0
                }

                if value.translation.width < -threshold {
                    // Swiped left → next page
                    layoutManager.nextPage()
                } else if value.translation.width > threshold {
                    // Swiped right → previous page
                    layoutManager.previousPage()
                }
            }
    }

    /// Briefly flash the page indicator to full opacity after a page switch.
    private func flashPageIndicator() {
        showPageIndicator = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showPageIndicator = false
        }
    }
}

// MARK: - Page Indicator

/// A row of dots indicating the current page, similar to iOS home screen dots.
struct PageIndicator: View {
    let pageCount: Int
    let activeIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == activeIndex ? Color.white : Color.white.opacity(0.35))
                    .frame(width: index == activeIndex ? 8 : 6,
                           height: index == activeIndex ? 8 : 6)
                    .animation(.easeInOut(duration: 0.2), value: activeIndex)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.black.opacity(0.3))
        )
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
