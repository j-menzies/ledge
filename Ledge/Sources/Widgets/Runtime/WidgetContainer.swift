import SwiftUI

/// SwiftUI wrapper that renders a single widget within the grid.
///
/// Provides the standard widget chrome: background (solid, blur, or transparent),
/// rounded corners, subtle border. Shows an error placeholder for
/// unknown or failed widget types.
struct WidgetContainer: View {
    @Environment(\.theme) private var theme
    @Environment(\.widgetBackgroundStyle) private var backgroundStyle
    let placement: WidgetPlacement
    let configStore: WidgetConfigStore
    let registry: WidgetRegistry

    var body: some View {
        Group {
            if let descriptor = registry.registeredTypes[placement.widgetTypeID] {
                descriptor.viewFactory(placement.id, configStore)
            } else {
                errorPlaceholder
            }
        }
        .background(widgetBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.widgetCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: theme.widgetCornerRadius)
                .strokeBorder(theme.widgetBorderColor, lineWidth: theme.widgetBorderWidth)
        )
    }

    @ViewBuilder
    private var widgetBackground: some View {
        switch backgroundStyle {
        case .solid:
            theme.widgetBackground
        case .blur:
            VisualEffectBlur(
                material: .hudWindow,
                blendingMode: .behindWindow,
                state: .active
            )
        case .transparent:
            Color.clear
        }
    }

    private var errorPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            Text("Unknown Widget")
                .font(.caption)
                .foregroundColor(theme.secondaryText)
            Text(placement.widgetTypeID)
                .font(.caption2.monospaced())
                .foregroundColor(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget Background Style Environment Key

private struct WidgetBackgroundStyleKey: EnvironmentKey {
    static let defaultValue: WidgetBackgroundStyle = .solid
}

extension EnvironmentValues {
    var widgetBackgroundStyle: WidgetBackgroundStyle {
        get { self[WidgetBackgroundStyleKey.self] }
        set { self[WidgetBackgroundStyleKey.self] = newValue }
    }
}
