import SwiftUI
import Combine

/// A simple clock widget — the first built-in widget.
///
/// Displays the current time in a large, readable format suited to the
/// Xeneon Edge's 2560x720 display.
struct ClockWidget {

    /// The descriptor used to register this widget with the WidgetRegistry.
    static let descriptor = WidgetDescriptor(
        typeID: "com.ledge.clock",
        displayName: "Clock",
        description: "Displays the current time",
        iconSystemName: "clock",
        minimumSize: .twoByTwo,
        defaultSize: .fourByFour,
        maximumSize: .sixBySix,
        defaultConfiguration: nil,
        viewFactory: { _, _ in
            AnyView(ClockWidgetView())
        },
        settingsFactory: nil
    )
}

// MARK: - Clock Widget View

struct ClockWidgetView: View {
    @Environment(\.theme) private var theme
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            Text(currentTime, style: .time)
                .font(.system(size: 56, weight: .thin, design: .monospaced))
                .foregroundColor(theme.primaryText)
                .minimumScaleFactor(0.3)
                .lineLimit(1)

            Text(currentTime, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { time in
            currentTime = time
        }
    }
}
