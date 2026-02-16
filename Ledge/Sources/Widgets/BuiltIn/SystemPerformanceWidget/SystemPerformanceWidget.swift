import SwiftUI
import Combine

/// System performance widget showing CPU, Memory, Disk usage, and Network bandwidth.
struct SystemPerformanceWidget {

    struct Config: Codable, Equatable {
        var showCPU: Bool = true
        var showMemory: Bool = true
        var showDisk: Bool = true
        var showNetwork: Bool = true
    }

    static let descriptor = WidgetDescriptor(
        typeID: "com.ledge.system-performance",
        displayName: "System Performance",
        description: "CPU, Memory, Disk & Network bandwidth",
        iconSystemName: "gauge.with.dots.needle.33percent",
        minimumSize: .fourByThree,
        defaultSize: .sixByFour,
        maximumSize: .tenBySix,
        defaultConfiguration: try? JSONEncoder().encode(Config()),
        viewFactory: { instanceID, configStore in
            AnyView(SystemPerformanceWidgetView(instanceID: instanceID, configStore: configStore))
        },
        settingsFactory: { instanceID, configStore in
            AnyView(SystemPerformanceSettingsView(instanceID: instanceID, configStore: configStore))
        }
    )
}

// MARK: - View

struct SystemPerformanceWidgetView: View {
    @Environment(\.theme) private var theme
    let instanceID: UUID
    let configStore: WidgetConfigStore

    @State private var config = SystemPerformanceWidget.Config()
    private let provider = SystemPerformanceProvider()

    @State private var metrics = SystemPerformanceProvider.Metrics()
    @State private var cpuHistory: [Double] = []
    @State private var memHistory: [Double] = []
    @State private var downloadHistory: [Double] = []
    @State private var uploadHistory: [Double] = []

    private let maxHistory = 60
    private let pollTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 200

            if isCompact {
                compactLayout
            } else {
                fullLayout
            }
        }
        .onAppear {
            loadConfig()
            refreshMetrics()
        }
        .onReceive(pollTimer) { _ in refreshMetrics() }
        .onReceive(configStore.configDidChange) { changedID in
            if changedID == instanceID { loadConfig() }
        }
    }

    // MARK: - Full Layout (2+ rows)

    private var fullLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            if config.showCPU {
                MetricCard(
                    icon: "cpu",
                    label: "CPU",
                    value: String(format: "%.0f%%", metrics.cpuUsage),
                    percent: metrics.cpuUsage / 100.0,
                    history: cpuHistory,
                    color: cpuColor,
                    theme: theme
                )
            }

            if config.showMemory {
                MetricCard(
                    icon: "memorychip",
                    label: "Memory",
                    value: String(format: "%.1f / %.0f GB", metrics.memoryUsed, metrics.memoryTotal),
                    percent: metrics.memoryPercent / 100.0,
                    history: memHistory,
                    color: memColor,
                    theme: theme
                )
            }

            if config.showDisk {
                MetricCard(
                    icon: "internaldrive",
                    label: "Disk",
                    value: String(format: "%.0f / %.0f GB", metrics.diskUsed, metrics.diskTotal),
                    percent: metrics.diskPercent / 100.0,
                    history: [],
                    color: diskColor,
                    theme: theme
                )
            }

            if config.showNetwork {
                NetworkCard(
                    downloadHistory: downloadHistory,
                    uploadHistory: uploadHistory,
                    currentDown: metrics.networkDownBytesPerSec,
                    currentUp: metrics.networkUpBytesPerSec,
                    theme: theme
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Compact Layout (1 row)

    private var compactLayout: some View {
        HStack(spacing: 16) {
            if config.showCPU {
                CompactMetric(
                    icon: "cpu",
                    value: String(format: "%.0f%%", metrics.cpuUsage),
                    percent: metrics.cpuUsage / 100.0,
                    color: cpuColor,
                    theme: theme
                )
            }
            if config.showMemory {
                CompactMetric(
                    icon: "memorychip",
                    value: String(format: "%.0f%%", metrics.memoryPercent),
                    percent: metrics.memoryPercent / 100.0,
                    color: memColor,
                    theme: theme
                )
            }
            if config.showDisk {
                CompactMetric(
                    icon: "internaldrive",
                    value: String(format: "%.0f%%", metrics.diskPercent),
                    percent: metrics.diskPercent / 100.0,
                    color: diskColor,
                    theme: theme
                )
            }
            if config.showNetwork {
                VStack(spacing: 4) {
                    Image(systemName: "wifi")
                        .font(.system(size: 18))
                        .foregroundColor(.cyan)
                    Text(formatRate(metrics.networkDownBytesPerSec))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.cyan)
                    Text(formatRate(metrics.networkUpBytesPerSec))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Colors

    private var cpuColor: Color {
        if metrics.cpuUsage > 80 { return .red }
        if metrics.cpuUsage > 50 { return .orange }
        return .green
    }

    private var memColor: Color {
        if metrics.memoryPercent > 85 { return .red }
        if metrics.memoryPercent > 60 { return .orange }
        return .blue
    }

    private var diskColor: Color {
        if metrics.diskPercent > 90 { return .red }
        if metrics.diskPercent > 75 { return .orange }
        return .purple
    }

    // MARK: - Helpers

    private func refreshMetrics() {
        let p = provider
        Task.detached {
            let m = p.collect()
            await MainActor.run {
                metrics = m

                cpuHistory.append(m.cpuUsage / 100.0)
                if cpuHistory.count > maxHistory { cpuHistory.removeFirst() }

                memHistory.append(m.memoryPercent / 100.0)
                if memHistory.count > maxHistory { memHistory.removeFirst() }

                downloadHistory.append(m.networkDownBytesPerSec)
                if downloadHistory.count > maxHistory { downloadHistory.removeFirst() }

                uploadHistory.append(m.networkUpBytesPerSec)
                if uploadHistory.count > maxHistory { uploadHistory.removeFirst() }
            }
        }
    }

    private func loadConfig() {
        if let saved: SystemPerformanceWidget.Config = configStore.read(instanceID: instanceID, as: SystemPerformanceWidget.Config.self) {
            config = saved
        }
    }
}

// MARK: - Metric Card (Full Layout)

private struct MetricCard: View {
    let icon: String
    let label: String
    let value: String
    let percent: Double
    let history: [Double]
    let color: Color
    let theme: LedgeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.primaryText)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.primaryText.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * min(percent, 1.0))
                }
            }
            .frame(height: 6)

            // Sparkline graph
            if !history.isEmpty {
                SparklineView(data: history, color: color)
                    .frame(height: 30)
            }
        }
    }
}

// MARK: - Network Card

private struct NetworkCard: View {
    let downloadHistory: [Double]
    let uploadHistory: [Double]
    let currentDown: Double
    let currentUp: Double
    let theme: LedgeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with current rates
            HStack {
                Image(systemName: "wifi")
                    .font(.system(size: 14))
                    .foregroundColor(.cyan)
                    .frame(width: 18)
                Text("Network")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                Spacer()
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                        Text(formatRate(currentDown))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                        Text(formatRate(currentUp))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }
            }

            // Bidirectional graph
            GeometryReader { geo in
                let isVertical = geo.size.height > geo.size.width
                BandwidthGraphView(
                    downloadHistory: downloadHistory,
                    uploadHistory: uploadHistory,
                    isVertical: isVertical,
                    theme: theme
                )
            }
            .frame(minHeight: 50)
        }
    }
}

// MARK: - Bandwidth Graph (bidirectional, orientation-aware)

private struct BandwidthGraphView: View {
    let downloadHistory: [Double]
    let uploadHistory: [Double]
    let isVertical: Bool
    let theme: LedgeTheme

    private let downloadColor: Color = .cyan
    private let uploadColor: Color = .orange

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Canvas { context, size in
                let maxVal = max(
                    downloadHistory.max() ?? 0,
                    uploadHistory.max() ?? 0,
                    1024 // minimum 1 KB/s scale
                )
                let count = max(downloadHistory.count, uploadHistory.count)
                guard count > 1 else { return }

                if isVertical {
                    drawVertical(context: context, size: size, maxVal: maxVal, count: count)
                } else {
                    drawHorizontal(context: context, size: size, maxVal: maxVal, count: count)
                }
            }

            // Center line
            if isVertical {
                Path { path in
                    path.move(to: CGPoint(x: w / 2, y: 0))
                    path.addLine(to: CGPoint(x: w / 2, y: h))
                }
                .stroke(theme.primaryText.opacity(0.15), lineWidth: 0.5)
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h / 2))
                    path.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(theme.primaryText.opacity(0.15), lineWidth: 0.5)
            }
        }
    }

    // Horizontal: X=time, download above center, upload below center
    private func drawHorizontal(context: GraphicsContext, size: CGSize, maxVal: Double, count: Int) {
        let w = size.width
        let h = size.height
        let mid = h / 2

        // Download (above center line)
        if !downloadHistory.isEmpty {
            var downFill = Path()
            downFill.move(to: CGPoint(x: 0, y: mid))
            for (i, val) in downloadHistory.enumerated() {
                let x = w * Double(i) / Double(count - 1)
                let y = mid - (mid * min(val / maxVal, 1.0))
                downFill.addLine(to: CGPoint(x: x, y: y))
            }
            downFill.addLine(to: CGPoint(x: w * Double(downloadHistory.count - 1) / Double(count - 1), y: mid))
            downFill.closeSubpath()
            context.fill(downFill, with: .color(downloadColor.opacity(0.3)))

            var downLine = Path()
            for (i, val) in downloadHistory.enumerated() {
                let x = w * Double(i) / Double(count - 1)
                let y = mid - (mid * min(val / maxVal, 1.0))
                if i == 0 { downLine.move(to: CGPoint(x: x, y: y)) }
                else { downLine.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(downLine, with: .color(downloadColor), lineWidth: 1.5)
        }

        // Upload (below center line)
        if !uploadHistory.isEmpty {
            var upFill = Path()
            upFill.move(to: CGPoint(x: 0, y: mid))
            for (i, val) in uploadHistory.enumerated() {
                let x = w * Double(i) / Double(count - 1)
                let y = mid + (mid * min(val / maxVal, 1.0))
                upFill.addLine(to: CGPoint(x: x, y: y))
            }
            upFill.addLine(to: CGPoint(x: w * Double(uploadHistory.count - 1) / Double(count - 1), y: mid))
            upFill.closeSubpath()
            context.fill(upFill, with: .color(uploadColor.opacity(0.3)))

            var upLine = Path()
            for (i, val) in uploadHistory.enumerated() {
                let x = w * Double(i) / Double(count - 1)
                let y = mid + (mid * min(val / maxVal, 1.0))
                if i == 0 { upLine.move(to: CGPoint(x: x, y: y)) }
                else { upLine.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(upLine, with: .color(uploadColor), lineWidth: 1.5)
        }
    }

    // Vertical: Y=time (top to bottom), download right of center, upload left of center
    private func drawVertical(context: GraphicsContext, size: CGSize, maxVal: Double, count: Int) {
        let w = size.width
        let h = size.height
        let mid = w / 2

        // Download (right of center)
        if !downloadHistory.isEmpty {
            var downFill = Path()
            downFill.move(to: CGPoint(x: mid, y: 0))
            for (i, val) in downloadHistory.enumerated() {
                let y = h * Double(i) / Double(count - 1)
                let x = mid + (mid * min(val / maxVal, 1.0))
                downFill.addLine(to: CGPoint(x: x, y: y))
            }
            downFill.addLine(to: CGPoint(x: mid, y: h * Double(downloadHistory.count - 1) / Double(count - 1)))
            downFill.closeSubpath()
            context.fill(downFill, with: .color(downloadColor.opacity(0.3)))

            var downLine = Path()
            for (i, val) in downloadHistory.enumerated() {
                let y = h * Double(i) / Double(count - 1)
                let x = mid + (mid * min(val / maxVal, 1.0))
                if i == 0 { downLine.move(to: CGPoint(x: x, y: y)) }
                else { downLine.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(downLine, with: .color(downloadColor), lineWidth: 1.5)
        }

        // Upload (left of center)
        if !uploadHistory.isEmpty {
            var upFill = Path()
            upFill.move(to: CGPoint(x: mid, y: 0))
            for (i, val) in uploadHistory.enumerated() {
                let y = h * Double(i) / Double(count - 1)
                let x = mid - (mid * min(val / maxVal, 1.0))
                upFill.addLine(to: CGPoint(x: x, y: y))
            }
            upFill.addLine(to: CGPoint(x: mid, y: h * Double(uploadHistory.count - 1) / Double(count - 1)))
            upFill.closeSubpath()
            context.fill(upFill, with: .color(uploadColor.opacity(0.3)))

            var upLine = Path()
            for (i, val) in uploadHistory.enumerated() {
                let y = h * Double(i) / Double(count - 1)
                let x = mid - (mid * min(val / maxVal, 1.0))
                if i == 0 { upLine.move(to: CGPoint(x: x, y: y)) }
                else { upLine.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(upLine, with: .color(uploadColor), lineWidth: 1.5)
        }
    }
}

// MARK: - Compact Metric (Single Row)

private struct CompactMetric: View {
    let icon: String
    let value: String
    let percent: Double
    let color: Color
    let theme: LedgeTheme

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(theme.primaryText)

            // Circular progress
            ZStack {
                Circle()
                    .stroke(theme.primaryText.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(percent, 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 40, height: 40)
        }
    }
}

// MARK: - Sparkline Graph

private struct SparklineView: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            if data.count > 1 {
                // Line
                Path { path in
                    for (index, value) in data.enumerated() {
                        let x = width * Double(index) / Double(data.count - 1)
                        let y = height * (1 - min(value, 1.0))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, lineWidth: 1.5)

                // Fill
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    for (index, value) in data.enumerated() {
                        let x = width * Double(index) / Double(data.count - 1)
                        let y = height * (1 - min(value, 1.0))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}

// MARK: - Rate Formatting

private func formatRate(_ bytesPerSec: Double) -> String {
    if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
    if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
    if bytesPerSec < 1024 * 1024 * 1024 { return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024)) }
    return String(format: "%.2f GB/s", bytesPerSec / (1024 * 1024 * 1024))
}

// MARK: - Settings

struct SystemPerformanceSettingsView: View {
    let instanceID: UUID
    let configStore: WidgetConfigStore

    @State private var config = SystemPerformanceWidget.Config()

    var body: some View {
        Form {
            Toggle("Show CPU", isOn: $config.showCPU)
            Toggle("Show Memory", isOn: $config.showMemory)
            Toggle("Show Disk", isOn: $config.showDisk)
            Toggle("Show Network", isOn: $config.showNetwork)
        }
        .onAppear { loadConfig() }
        .onChange(of: config) { _, _ in saveConfig() }
    }

    private func loadConfig() {
        if let saved: SystemPerformanceWidget.Config = configStore.read(instanceID: instanceID, as: SystemPerformanceWidget.Config.self) {
            config = saved
        }
    }

    private func saveConfig() {
        configStore.write(instanceID: instanceID, value: config)
    }
}
