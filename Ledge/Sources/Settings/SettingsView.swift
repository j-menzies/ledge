import SwiftUI

/// Settings window displayed on the primary monitor.
///
/// This is where the user configures Ledge — display selection, layout editing,
/// widget management, etc. It's a standard SwiftUI window (not a non-activating panel)
/// because settings interaction needs full keyboard/mouse focus.
struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject var displayManager: DisplayManager
    let layoutManager: LayoutManager
    let configStore: WidgetConfigStore

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink(destination: DisplaySettingsView()) {
                    Label("Display", systemImage: "display")
                }
                NavigationLink(destination: WidgetSettingsView(layoutManager: layoutManager, configStore: configStore)) {
                    Label("Widgets", systemImage: "square.grid.2x2")
                }
                NavigationLink(destination: LayoutEditorView(layoutManager: layoutManager)) {
                    Label("Layout", systemImage: "rectangle.3.group")
                }
                NavigationLink(destination: AppearanceSettingsView()) {
                    Label("Appearance", systemImage: "paintpalette")
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
        .environment(\.theme, themeManager.resolvedTheme)
    }
}

// MARK: - Display Settings

struct DisplaySettingsView: View {
    @EnvironmentObject var displayManager: DisplayManager

    /// True when macOS shows a menu bar on every display (the default).
    private var hasSeparateSpaces: Bool { NSScreen.screensHaveSeparateSpaces }

    var body: some View {
        Form {
            // Show a prominent alert when the system setting causes a menu bar on the Edge
            if hasSeparateSpaces && displayManager.xeneonScreen != nil {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Menu bar appears on the Xeneon Edge")
                                .font(.headline)
                        }

                        Text("macOS shows a menu bar on every display when \"Displays have separate Spaces\" is enabled. Disabling it removes the menu bar from secondary displays like the Xeneon Edge.")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("To fix:")
                                .font(.subheadline.bold())
                            Text("1. Open **System Settings** > **Desktop & Dock**")
                            Text("2. Scroll to **Mission Control**")
                            Text("3. Turn off **Displays have separate Spaces**")
                            Text("4. Log out and back in for the change to take effect")
                        }
                        .font(.callout)

                        Button("Open Desktop & Dock Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }

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
                LabeledContent("Accessibility") {
                    HStack {
                        Image(systemName: displayManager.accessibilityPermission == .granted
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(displayManager.accessibilityPermission == .granted ? .green : .orange)
                        Text(displayManager.accessibilityPermission.rawValue)
                    }
                }

                LabeledContent("Event Tap") {
                    HStack {
                        Image(systemName: displayManager.isTouchRemapperActive ? "hand.tap.fill" : "hand.tap")
                            .foregroundColor(displayManager.isTouchRemapperActive ? .green : .secondary)
                        Text(displayManager.isTouchRemapperActive ? "Active" : "Inactive")
                    }
                }

                LabeledContent("Calibration") {
                    HStack {
                        Image(systemName: (displayManager.calibrationState == .calibrated
                              || displayManager.calibrationState == .autoDetected)
                              ? "target" : "questionmark.circle")
                            .foregroundColor((displayManager.calibrationState == .calibrated
                              || displayManager.calibrationState == .autoDetected) ? .green : .secondary)
                        Text(displayManager.calibrationState.rawValue)
                    }
                }

                if let deviceID = displayManager.learnedDeviceID {
                    LabeledContent("Device ID") {
                        Text("\(deviceID)")
                            .font(.caption.monospaced())
                    }
                }

                Text("macOS maps the Xeneon Edge touchscreen to the primary display. The touch remapper auto-detects the touchscreen via USB and redirects input to the correct screen.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !displayManager.isTouchRemapperActive {
                    Button("Enable Touch Remapping") {
                        displayManager.startTouchRemapper()
                    }
                    .disabled(displayManager.xeneonScreen == nil)
                } else {
                    if displayManager.calibrationState == .notStarted {
                        Button("Calibrate Touch (Manual)") {
                            displayManager.calibrateTouch()
                        }
                        .help("Touch the Xeneon Edge screen to identify the touchscreen device")
                    } else {
                        Button("Re-detect Device") {
                            displayManager.stopTouchRemapper()
                            displayManager.startTouchRemapper()
                        }
                        .help("Re-run IOKit HID detection for the touchscreen device")
                    }

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

// MARK: - Widget Settings

struct WidgetSettingsView: View {
    let layoutManager: LayoutManager
    let configStore: WidgetConfigStore
    let registry = WidgetRegistry.shared

    @State private var showAddWidget = false

    var body: some View {
        Form {
            Section("Active Widgets") {
                if layoutManager.activeLayout.placements.isEmpty {
                    Text("No widgets placed. Click + to add one.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(layoutManager.activeLayout.placements) { placement in
                        DisclosureGroup {
                            widgetConfigContent(placement)
                        } label: {
                            widgetRow(placement)
                        }
                    }
                }
            }

            Section {
                Button {
                    showAddWidget = true
                } label: {
                    Label("Add Widget", systemImage: "plus.circle")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Widgets")
        .sheet(isPresented: $showAddWidget) {
            AddWidgetSheet(layoutManager: layoutManager, configStore: configStore)
        }
    }

    private func widgetRow(_ placement: WidgetPlacement) -> some View {
        let descriptor = registry.registeredTypes[placement.widgetTypeID]
        return HStack {
            Image(systemName: descriptor?.iconSystemName ?? "questionmark.square")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading) {
                Text(descriptor?.displayName ?? placement.widgetTypeID)
                    .font(.body)
                Text("Col \(placement.column), Row \(placement.row) — \(placement.columnSpan)x\(placement.rowSpan)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func widgetConfigContent(_ placement: WidgetPlacement) -> some View {
        // Widget-specific settings
        if let settingsView = registry.createSettingsView(
            typeID: placement.widgetTypeID,
            instanceID: placement.id,
            configStore: configStore
        ) {
            Section("Widget Settings") {
                settingsView
            }
        }

        // Delete button
        Section {
            Button(role: .destructive) {
                layoutManager.removeWidget(id: placement.id)
            } label: {
                Label("Remove Widget", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add Widget Sheet

struct AddWidgetSheet: View {
    let layoutManager: LayoutManager
    let configStore: WidgetConfigStore
    let registry = WidgetRegistry.shared

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Widget")
                .font(.headline)
                .padding()

            List(registry.allTypes, id: \.typeID) { descriptor in
                Button {
                    addWidget(descriptor)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: descriptor.iconSystemName)
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                            .frame(width: 32)
                        VStack(alignment: .leading) {
                            Text(descriptor.displayName)
                                .font(.body)
                            Text(descriptor.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(descriptor.defaultSize.columns)x\(descriptor.defaultSize.rows)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 400, height: 400)
    }

    private func addWidget(_ descriptor: WidgetDescriptor) {
        let placement = WidgetPlacement(
            id: UUID(),
            widgetTypeID: descriptor.typeID,
            column: 0,
            row: 0,
            columnSpan: descriptor.defaultSize.columns,
            rowSpan: descriptor.defaultSize.rows,
            configuration: descriptor.defaultConfiguration
        )
        layoutManager.addWidget(placement)
    }
}

// MARK: - Layout Editor (Graphical)

struct LayoutEditorView: View {
    let layoutManager: LayoutManager

    @State private var selectedWidgetID: UUID?
    @State private var showAddWidget = false

    var body: some View {
        VStack(spacing: 0) {
            // Grid editor
            InteractiveGridEditor(
                layoutManager: layoutManager,
                selectedWidgetID: $selectedWidgetID
            )
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .padding(16)

            Divider()

            // Selected widget details / widget list
            Form {
                if let selectedID = selectedWidgetID,
                   let placement = layoutManager.activeLayout.placements.first(where: { $0.id == selectedID }) {
                    selectedWidgetSection(placement)
                } else {
                    Section("Widgets") {
                        Text("Click a widget in the grid above to select it, then drag to reposition or resize.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(layoutManager.activeLayout.placements) { placement in
                            let descriptor = WidgetRegistry.shared.registeredTypes[placement.widgetTypeID]
                            Button {
                                selectedWidgetID = placement.id
                            } label: {
                                HStack {
                                    Image(systemName: descriptor?.iconSystemName ?? "questionmark.square")
                                        .foregroundColor(.accentColor)
                                    Text(descriptor?.displayName ?? placement.widgetTypeID)
                                    Spacer()
                                    Text("\(placement.columnSpan)x\(placement.rowSpan) at (\(placement.column),\(placement.row))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Layout") {
                    LabeledContent("Grid") {
                        Text("\(layoutManager.activeLayout.columns) x \(layoutManager.activeLayout.rows)")
                    }
                    LabeledContent("Widgets") {
                        Text("\(layoutManager.activeLayout.placements.count)")
                    }
                }

                Section("Saved Layouts") {
                    ForEach(layoutManager.savedLayouts) { layout in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(layout.name)
                                Text("\(layout.placements.count) widgets")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if layout.id == layoutManager.activeLayout.id {
                                Text("Active")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.2))
                                    .clipShape(Capsule())
                            } else {
                                Button("Switch") {
                                    layoutManager.switchLayout(to: layout)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Layout")
    }

    @ViewBuilder
    private func selectedWidgetSection(_ placement: WidgetPlacement) -> some View {
        let descriptor = WidgetRegistry.shared.registeredTypes[placement.widgetTypeID]
        let grid = layoutManager.activeLayout

        Section("Selected: \(descriptor?.displayName ?? placement.widgetTypeID)") {
            HStack {
                Text("Position")
                Spacer()
                Stepper("Col \(placement.column)", value: Binding(
                    get: { placement.column },
                    set: { var p = placement; p.column = $0; layoutManager.updateWidget(p) }
                ), in: 0...(grid.columns - placement.columnSpan))
            }

            HStack {
                Text("")
                Spacer()
                Stepper("Row \(placement.row)", value: Binding(
                    get: { placement.row },
                    set: { var p = placement; p.row = $0; layoutManager.updateWidget(p) }
                ), in: 0...(grid.rows - placement.rowSpan))
            }

            HStack {
                Text("Size")
                Spacer()
                Stepper("\(placement.columnSpan)w", value: Binding(
                    get: { placement.columnSpan },
                    set: { var p = placement; p.columnSpan = $0; layoutManager.updateWidget(p) }
                ), in: 1...(grid.columns - placement.column))
            }

            HStack {
                Text("")
                Spacer()
                Stepper("\(placement.rowSpan)h", value: Binding(
                    get: { placement.rowSpan },
                    set: { var p = placement; p.rowSpan = $0; layoutManager.updateWidget(p) }
                ), in: 1...(grid.rows - placement.row))
            }

            HStack {
                Button("Deselect") {
                    selectedWidgetID = nil
                }
                Spacer()
                Button(role: .destructive) {
                    layoutManager.removeWidget(id: placement.id)
                    selectedWidgetID = nil
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Interactive Grid Editor

struct InteractiveGridEditor: View {
    let layoutManager: LayoutManager
    @Binding var selectedWidgetID: UUID?

    @State private var dragOffset: CGSize = .zero
    @State private var draggingWidgetID: UUID?
    @State private var resizingWidgetID: UUID?
    @State private var resizeOffset: CGSize = .zero

    private let widgetColors: [Color] = [
        .blue, .purple, .green, .orange, .pink, .cyan, .indigo, .teal, .mint, .yellow
    ]

    var body: some View {
        GeometryReader { geometry in
            let layout = layoutManager.activeLayout
            let gap: CGFloat = 3
            let cellW = (geometry.size.width - CGFloat(layout.columns - 1) * gap) / CGFloat(layout.columns)
            let cellH = (geometry.size.height - CGFloat(layout.rows - 1) * gap) / CGFloat(layout.rows)

            ZStack(alignment: .topLeading) {
                // Grid background cells
                ForEach(0..<layout.columns, id: \.self) { col in
                    ForEach(0..<layout.rows, id: \.self) { row in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.08))
                            .frame(width: cellW, height: cellH)
                            .offset(
                                x: CGFloat(col) * (cellW + gap),
                                y: CGFloat(row) * (cellH + gap)
                            )
                    }
                }

                // Widget placements
                ForEach(Array(layout.placements.enumerated()), id: \.element.id) { index, placement in
                    let isSelected = placement.id == selectedWidgetID
                    let isDragging = placement.id == draggingWidgetID
                    let isResizing = placement.id == resizingWidgetID
                    let descriptor = WidgetRegistry.shared.registeredTypes[placement.widgetTypeID]
                    let color = widgetColors[index % widgetColors.count]

                    let w = CGFloat(placement.columnSpan) * cellW + CGFloat(placement.columnSpan - 1) * gap
                    let h = CGFloat(placement.rowSpan) * cellH + CGFloat(placement.rowSpan - 1) * gap
                    let x = CGFloat(placement.column) * (cellW + gap)
                    let y = CGFloat(placement.row) * (cellH + gap)

                    let resizedW = isResizing ? w + resizeOffset.width : w
                    let resizedH = isResizing ? h + resizeOffset.height : h

                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(color.opacity(isSelected ? 0.5 : 0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(isSelected ? color : color.opacity(0.5), lineWidth: isSelected ? 2 : 1)
                            )

                        VStack(spacing: 2) {
                            Image(systemName: descriptor?.iconSystemName ?? "questionmark.square")
                                .font(.system(size: 14))
                            Text(descriptor?.displayName ?? "?")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(isSelected ? .white : .primary)

                        // Resize handle (bottom-right corner)
                        if isSelected {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Image(systemName: "arrow.down.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white)
                                        .frame(width: 18, height: 18)
                                        .background(color.opacity(0.8))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                        .gesture(
                                            DragGesture()
                                                .onChanged { value in
                                                    resizingWidgetID = placement.id
                                                    resizeOffset = value.translation
                                                }
                                                .onEnded { value in
                                                    commitResize(placement: placement, cellW: cellW, cellH: cellH, gap: gap)
                                                    resizingWidgetID = nil
                                                    resizeOffset = .zero
                                                }
                                        )
                                }
                            }
                            .padding(2)
                        }
                    }
                    .frame(width: max(resizedW, cellW * 0.5), height: max(resizedH, cellH * 0.5))
                    .offset(
                        x: x + (isDragging ? dragOffset.width : 0),
                        y: y + (isDragging ? dragOffset.height : 0)
                    )
                    .zIndex(isSelected ? 10 : 0)
                    .onTapGesture {
                        selectedWidgetID = placement.id
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if resizingWidgetID == nil {
                                    draggingWidgetID = placement.id
                                    selectedWidgetID = placement.id
                                    dragOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                if draggingWidgetID == placement.id {
                                    commitDrag(placement: placement, cellW: cellW, cellH: cellH, gap: gap)
                                    draggingWidgetID = nil
                                    dragOffset = .zero
                                }
                            }
                    )
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func commitDrag(placement: WidgetPlacement, cellW: CGFloat, cellH: CGFloat, gap: CGFloat) {
        let layout = layoutManager.activeLayout
        let colDelta = Int((dragOffset.width / (cellW + gap)).rounded())
        let rowDelta = Int((dragOffset.height / (cellH + gap)).rounded())

        var p = placement
        p.column = max(0, min(layout.columns - p.columnSpan, p.column + colDelta))
        p.row = max(0, min(layout.rows - p.rowSpan, p.row + rowDelta))
        layoutManager.updateWidget(p)
    }

    private func commitResize(placement: WidgetPlacement, cellW: CGFloat, cellH: CGFloat, gap: CGFloat) {
        let layout = layoutManager.activeLayout
        let colDelta = Int((resizeOffset.width / (cellW + gap)).rounded())
        let rowDelta = Int((resizeOffset.height / (cellH + gap)).rounded())

        var p = placement
        p.columnSpan = max(1, min(layout.columns - p.column, p.columnSpan + colDelta))
        p.rowSpan = max(1, min(layout.rows - p.row, p.rowSpan + rowDelta))
        layoutManager.updateWidget(p)
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Mode", selection: Binding(
                    get: { themeManager.mode },
                    set: { themeManager.mode = $0 }
                )) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Auto follows the system appearance (Dark/Light).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Preview") {
                ThemePreviewCard(theme: themeManager.resolvedTheme)
                    .frame(height: 120)
            }

            Section("All Themes") {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        let isActive = themeManager.mode == mode
                        VStack(spacing: 6) {
                            ThemePreviewCard(theme: mode == .auto
                                ? (themeManager.systemIsDark ? .dark : .light)
                                : mode.theme
                            )
                            .frame(height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                            )

                            Text(mode.rawValue)
                                .font(.caption)
                                .foregroundColor(isActive ? .accentColor : .secondary)
                        }
                        .onTapGesture {
                            themeManager.mode = mode
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

// MARK: - Theme Preview Card

struct ThemePreviewCard: View {
    let theme: LedgeTheme

    var body: some View {
        ZStack {
            theme.dashboardBackground

            HStack(spacing: 6) {
                // Mock widget 1
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.widgetBackground)
                    .overlay(
                        VStack(spacing: 4) {
                            Text("10:54")
                                .font(.system(size: 14, weight: .light, design: .rounded))
                                .foregroundColor(theme.primaryText)
                            Text("Thursday")
                                .font(.system(size: 8))
                                .foregroundColor(theme.secondaryText)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(theme.widgetBorderColor, lineWidth: theme.widgetBorderWidth)
                    )

                // Mock widget 2
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.widgetBackground)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "cloud.sun.fill")
                                .font(.system(size: 14))
                                .foregroundColor(theme.primaryText)
                                .symbolRenderingMode(.hierarchical)
                            Text("-1°C")
                                .font(.system(size: 10))
                                .foregroundColor(theme.secondaryText)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(theme.widgetBorderColor, lineWidth: theme.widgetBorderWidth)
                    )

                // Mock widget 3
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.widgetBackground)
                    .overlay(
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Meeting")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(theme.primaryText)
                            Text("10:30 - 11:00")
                                .font(.system(size: 7))
                                .foregroundColor(theme.tertiaryText)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(theme.widgetBorderColor, lineWidth: theme.widgetBorderWidth)
                    )
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Ledge")
                .font(.largeTitle)
            Text("A macOS widget dashboard for the Corsair Xeneon Edge")
                .foregroundColor(.secondary)
            Text("Phase 1 — Widget Framework")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}
