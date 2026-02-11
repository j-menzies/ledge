import SwiftUI
import Combine

/// A simple clock widget — the first built-in widget.
///
/// Displays the current time in a large, readable format suited to the
/// Xeneon Edge's 2560×720 display. Supports analogue and digital styles
/// (digital only for Phase 0).
@Observable
class ClockWidget {

    var use24Hour: Bool = true
    var showSeconds: Bool = true
    var showDate: Bool = true

    /// The descriptor used to register this widget with the WidgetRegistry.
    static let descriptor = WidgetDescriptor(
        typeID: "com.ledge.clock",
        displayName: "Clock",
        description: "Displays the current time",
        minimumSize: .twoByOne,
        defaultSize: .twoByTwo,
        maximumSize: nil,
        viewFactory: {
            AnyView(ClockWidgetView())
        },
        settingsFactory: {
            AnyView(ClockSettingsView())
        }
    )
}

// MARK: - Clock Widget View

struct ClockWidgetView: View {
    @State private var currentTime = Date()
    @State private var widget = ClockWidget()

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            // Time
            Text(timeString)
                .font(.system(size: 56, weight: .thin, design: .monospaced))
                .foregroundColor(.white)
                .minimumScaleFactor(0.3)
                .lineLimit(1)

            // Date
            if widget.showDate {
                Text(dateString)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onReceive(timer) { time in
            currentTime = time
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        if widget.use24Hour {
            formatter.dateFormat = widget.showSeconds ? "HH:mm:ss" : "HH:mm"
        } else {
            formatter.dateFormat = widget.showSeconds ? "h:mm:ss a" : "h:mm a"
        }
        return formatter.string(from: currentTime)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter.string(from: currentTime)
    }
}

// MARK: - Clock Settings View

struct ClockSettingsView: View {
    @State private var widget = ClockWidget()

    var body: some View {
        Form {
            Toggle("24-hour format", isOn: $widget.use24Hour)
            Toggle("Show seconds", isOn: $widget.showSeconds)
            Toggle("Show date", isOn: $widget.showDate)
        }
    }
}

#Preview("Clock Widget") {
    ClockWidgetView()
        .frame(width: 400, height: 200)
        .background(.black)
}
