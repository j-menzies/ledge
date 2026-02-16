import SwiftUI
import UniformTypeIdentifiers

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

// MARK: - Add Widget Sheet (Visual Gallery)

struct AddWidgetSheet: View {
    let layoutManager: LayoutManager
    let configStore: WidgetConfigStore
    let registry = WidgetRegistry.shared

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: WidgetCategory? = nil
    @State private var hoveredWidget: String? = nil

    /// Widget categories for filtering
    enum WidgetCategory: String, CaseIterable {
        case media = "Media"
        case productivity = "Productivity"
        case system = "System"
        case smart = "Smart Home"
        case info = "Info"
        case web = "Web"
    }

    /// Map widget type IDs to categories
    private static let categoryMap: [String: WidgetCategory] = [
        "com.ledge.spotify": .media,
        "com.ledge.system-audio": .media,
        "com.ledge.google-meet": .media,
        "com.ledge.calendar": .productivity,
        "com.ledge.clock": .info,
        "com.ledge.datetime": .info,
        "com.ledge.weather": .info,
        "com.ledge.system-performance": .system,
        "com.ledge.homeassistant": .smart,
        "com.ledge.web": .web,
    ]

    /// Category color for each widget type
    private static let categoryColors: [WidgetCategory: Color] = [
        .media: .green,
        .productivity: .blue,
        .system: .orange,
        .smart: .purple,
        .info: .cyan,
        .web: .indigo,
    ]

    private var filteredWidgets: [WidgetDescriptor] {
        var widgets = registry.allTypes
        if let category = selectedCategory {
            widgets = widgets.filter { Self.categoryMap[$0.typeID] == category }
        }
        if !searchText.isEmpty {
            widgets = widgets.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        return widgets
    }

    /// Categories that actually have widgets in them
    private var activeCategories: [WidgetCategory] {
        WidgetCategory.allCases.filter { category in
            registry.allTypes.contains { Self.categoryMap[$0.typeID] == category }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Widget Gallery")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Search + category filters
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search widgets...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Category pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryPill(label: "All", category: nil)
                        ForEach(activeCategories, id: \.self) { category in
                            categoryPill(label: category.rawValue, category: category)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            // Widget grid
            if filteredWidgets.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No widgets match your search")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 12
                    ) {
                        ForEach(filteredWidgets, id: \.typeID) { descriptor in
                            widgetCard(descriptor)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 520, height: 560)
        .background(.background)
    }

    // MARK: - Category Pill

    private func categoryPill(label: String, category: WidgetCategory?) -> some View {
        let isSelected = (category == selectedCategory) || (category == nil && selectedCategory == nil)
        let pillColor = category.flatMap { Self.categoryColors[$0] } ?? .primary

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isSelected ? pillColor.opacity(0.2) : Color.clear)
                .foregroundStyle(isSelected ? pillColor : .secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? pillColor.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Widget Card

    private func widgetCard(_ descriptor: WidgetDescriptor) -> some View {
        let category = Self.categoryMap[descriptor.typeID] ?? .info
        let accentColor = Self.categoryColors[category] ?? .accentColor
        let isHovered = hoveredWidget == descriptor.typeID
        let isAlreadyAdded = layoutManager.activeLayout.placements.contains {
            $0.widgetTypeID == descriptor.typeID
        }

        return Button {
            addWidget(descriptor)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Icon header area
                HStack(alignment: .top) {
                    // Large icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: descriptor.iconSystemName)
                            .font(.system(size: 20))
                            .foregroundStyle(accentColor)
                    }

                    Spacer()

                    // Size badge + already added indicator
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(descriptor.defaultSize.columns)×\(descriptor.defaultSize.rows)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.secondary)

                        if isAlreadyAdded {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                Text("Added")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.bottom, 10)

                // Name
                Text(descriptor.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Description
                Text(descriptor.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // Category tag
                Text(category.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accentColor.opacity(0.8))
                    .padding(.top, 6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 150)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? accentColor.opacity(0.06) : Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? accentColor.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredWidget = hovering ? descriptor.typeID : nil
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Actions

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

    /// During a drag, tracks the snapped grid position (col, row) the widget is hovering over.
    @State private var dragSnappedCol: Int?
    @State private var dragSnappedRow: Int?
    @State private var draggingWidgetID: UUID?

    /// During a resize, tracks the snapped span.
    @State private var resizeSnappedCols: Int?
    @State private var resizeSnappedRows: Int?
    @State private var resizingWidgetID: UUID?

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

                    // Use snapped position/size during drag/resize, actual placement otherwise
                    let col = isDragging ? (dragSnappedCol ?? placement.column) : placement.column
                    let row = isDragging ? (dragSnappedRow ?? placement.row) : placement.row
                    let colSpan = isResizing ? (resizeSnappedCols ?? placement.columnSpan) : placement.columnSpan
                    let rowSpan = isResizing ? (resizeSnappedRows ?? placement.rowSpan) : placement.rowSpan

                    let w = CGFloat(colSpan) * cellW + CGFloat(colSpan - 1) * gap
                    let h = CGFloat(rowSpan) * cellH + CGFloat(rowSpan - 1) * gap
                    let x = CGFloat(col) * (cellW + gap)
                    let y = CGFloat(row) * (cellH + gap)

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
                                                    let newCols = max(1, min(
                                                        layout.columns - placement.column,
                                                        placement.columnSpan + Int((value.translation.width / (cellW + gap)).rounded())
                                                    ))
                                                    let newRows = max(1, min(
                                                        layout.rows - placement.row,
                                                        placement.rowSpan + Int((value.translation.height / (cellH + gap)).rounded())
                                                    ))
                                                    resizeSnappedCols = newCols
                                                    resizeSnappedRows = newRows
                                                }
                                                .onEnded { _ in
                                                    if let cols = resizeSnappedCols, let rows = resizeSnappedRows {
                                                        var p = placement
                                                        p.columnSpan = cols
                                                        p.rowSpan = rows
                                                        layoutManager.updateWidget(p)
                                                    }
                                                    resizingWidgetID = nil
                                                    resizeSnappedCols = nil
                                                    resizeSnappedRows = nil
                                                }
                                        )
                                }
                            }
                            .padding(2)
                        }
                    }
                    .frame(width: w, height: h)
                    .offset(x: x, y: y)
                    .animation(.easeOut(duration: 0.15), value: col)
                    .animation(.easeOut(duration: 0.15), value: row)
                    .animation(.easeOut(duration: 0.15), value: colSpan)
                    .animation(.easeOut(duration: 0.15), value: rowSpan)
                    .zIndex(isDragging || isSelected ? 10 : 0)
                    .opacity(isDragging ? 0.8 : 1.0)
                    .onTapGesture {
                        selectedWidgetID = placement.id
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if resizingWidgetID == nil {
                                    draggingWidgetID = placement.id
                                    selectedWidgetID = placement.id
                                    let newCol = max(0, min(
                                        layout.columns - placement.columnSpan,
                                        placement.column + Int((value.translation.width / (cellW + gap)).rounded())
                                    ))
                                    let newRow = max(0, min(
                                        layout.rows - placement.rowSpan,
                                        placement.row + Int((value.translation.height / (cellH + gap)).rounded())
                                    ))
                                    dragSnappedCol = newCol
                                    dragSnappedRow = newRow
                                }
                            }
                            .onEnded { _ in
                                if let col = dragSnappedCol, let row = dragSnappedRow {
                                    var p = placement
                                    p.column = col
                                    p.row = row
                                    layoutManager.updateWidget(p)
                                }
                                draggingWidgetID = nil
                                dragSnappedCol = nil
                                dragSnappedRow = nil
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
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var showingImagePicker = false

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

            Section("Widget Background") {
                Picker("Style", selection: Binding(
                    get: { themeManager.widgetBackgroundStyle },
                    set: { themeManager.widgetBackgroundStyle = $0 }
                )) {
                    ForEach(WidgetBackgroundStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)

                switch themeManager.widgetBackgroundStyle {
                case .solid:
                    Text("Widgets have a solid background from the active theme.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .blur:
                    Text("Widgets blur the content behind them, creating a frosted glass effect. Works best with a background image.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .transparent:
                    Text("Widgets have no background — content floats directly over the dashboard background.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Dashboard Background") {
                Picker("Background", selection: Binding(
                    get: { themeManager.dashboardBackgroundMode },
                    set: { themeManager.dashboardBackgroundMode = $0 }
                )) {
                    ForEach(DashboardBackgroundMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                if themeManager.dashboardBackgroundMode == .image {
                    HStack {
                        if !themeManager.backgroundImagePath.isEmpty {
                            Text(URL(fileURLWithPath: themeManager.backgroundImagePath).lastPathComponent)
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No image selected")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Choose Image...") {
                            chooseBackgroundImage()
                        }
                    }

                    if let image = themeManager.backgroundImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Text("For best results, use a 2560×720 image. Corsair iCUE includes excellent wallpapers for the Xeneon Edge.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a background image for the Xeneon Edge dashboard"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            themeManager.backgroundImagePath = url.path
        }
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
