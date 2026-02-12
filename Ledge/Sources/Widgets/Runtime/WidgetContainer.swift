import SwiftUI

/// SwiftUI wrapper that renders a single widget within the grid.
///
/// Provides the standard widget chrome: semi-transparent background,
/// rounded corners, subtle border. Shows an error placeholder for
/// unknown or failed widget types.
struct WidgetContainer: View {
    @Environment(\.theme) private var theme
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
        .background(theme.widgetBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.widgetCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: theme.widgetCornerRadius)
                .strokeBorder(theme.widgetBorderColor, lineWidth: theme.widgetBorderWidth)
        )
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
