import SwiftUI
import Combine

/// The root view displayed on the Xeneon Edge panel.
///
/// This view hosts the grid layout and renders all active widgets.
/// For Phase 0, it shows a simple placeholder to validate that the panel
/// is working correctly.
struct DashboardView: View {
    @EnvironmentObject var displayManager: DisplayManager

    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Title
                Text("Ledge")
                    .font(.system(size: 48, weight: .ultraLight, design: .default))
                    .foregroundColor(.white)

                // Clock — simple proof that the panel is rendering and updating
                Text(currentTime, style: .time)
                    .font(.system(size: 72, weight: .thin, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))

                // Status
                Text(displayManager.statusMessage)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))

                Spacer().frame(height: 20)

                // Touch test — tap this to verify non-focus-stealing behaviour
                TouchTestView()
            }
            .padding(40)
        }
        .onReceive(timer) { time in
            currentTime = time
        }
    }
}

/// A simple view to test touch interaction.
/// Tap the circle and it changes colour — verifying that touch events
/// reach the panel without stealing focus from the primary display.
struct TouchTestView: View {
    @State private var tapCount = 0
    @State private var isPressed = false

    private let colours: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .yellow, .red
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("Touch Test")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            Circle()
                .fill(colours[tapCount % colours.count])
                .frame(width: 80, height: 80)
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
                .onTapGesture {
                    tapCount += 1
                }
                .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
                    isPressed = pressing
                }, perform: {})

            Text("Taps: \(tapCount)")
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            Text("Tap the circle. Your foreground app should stay focused.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(DisplayManager())
        .frame(width: 2560, height: 720)
        .background(.black)
}
