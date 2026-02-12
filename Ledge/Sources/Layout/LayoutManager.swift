import Foundation
import os.log

/// Manages the active widget layout and persists layouts to disk.
///
/// Stores layouts as JSON in `~/Library/Application Support/Ledge/layouts/`.
/// On first launch, creates and saves the default layout.
@Observable
class LayoutManager {

    private let logger = Logger(subsystem: "com.ledge.app", category: "LayoutManager")
    private let directory: URL
    private let activeLayoutFile: URL

    /// The currently active layout rendered on the Xeneon Edge.
    var activeLayout: WidgetLayout

    /// All saved layouts.
    var savedLayouts: [WidgetLayout] = []

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("Ledge/layouts", isDirectory: true)
        activeLayoutFile = directory.appendingPathComponent("active.json")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Load active layout or use default
        if let data = try? Data(contentsOf: activeLayoutFile),
           let layout = try? JSONDecoder().decode(WidgetLayout.self, from: data) {
            activeLayout = layout
        } else {
            activeLayout = WidgetLayout.defaultLayout
        }

        loadSavedLayouts()

        // Persist immediately so widget instance UUIDs are stable across launches.
        // Without this, the default layout's UUIDs would be regenerated on every
        // launch (since WidgetLayout.defaultLayout creates new UUIDs), orphaning
        // any saved widget configs.
        save()
    }

    // MARK: - Widget Management

    /// Add a widget placement to the active layout.
    func addWidget(_ placement: WidgetPlacement) {
        activeLayout.placements.append(placement)
        save()
    }

    /// Remove a widget placement from the active layout by its ID.
    func removeWidget(id: UUID) {
        activeLayout.placements.removeAll { $0.id == id }
        save()
    }

    /// Update a widget placement in the active layout.
    func updateWidget(_ placement: WidgetPlacement) {
        if let index = activeLayout.placements.firstIndex(where: { $0.id == placement.id }) {
            activeLayout.placements[index] = placement
            save()
        }
    }

    // MARK: - Layout Management

    /// Switch to a different saved layout.
    func switchLayout(to layout: WidgetLayout) {
        activeLayout = layout
        save()
    }

    /// Save the active layout to disk.
    func save() {
        do {
            let data = try JSONEncoder().encode(activeLayout)
            try data.write(to: activeLayoutFile, options: .atomic)
        } catch {
            logger.error("Failed to save active layout: \(error.localizedDescription)")
        }

        // Also save to the layouts list
        if let index = savedLayouts.firstIndex(where: { $0.id == activeLayout.id }) {
            savedLayouts[index] = activeLayout
        } else {
            savedLayouts.append(activeLayout)
        }
        saveSavedLayouts()
    }

    /// Create a new layout with the given name (copies current as starting point).
    func createLayout(name: String) -> WidgetLayout {
        var layout = activeLayout
        layout = WidgetLayout(
            id: UUID(),
            name: name,
            columns: activeLayout.columns,
            rows: activeLayout.rows,
            placements: activeLayout.placements
        )
        savedLayouts.append(layout)
        saveSavedLayouts()
        return layout
    }

    /// Delete a saved layout by ID. Cannot delete the active layout.
    func deleteLayout(id: UUID) {
        guard id != activeLayout.id else {
            logger.warning("Cannot delete the active layout")
            return
        }
        savedLayouts.removeAll { $0.id == id }
        saveSavedLayouts()
    }

    // MARK: - Persistence

    private func loadSavedLayouts() {
        let listFile = directory.appendingPathComponent("layouts-list.json")
        guard let data = try? Data(contentsOf: listFile),
              let layouts = try? JSONDecoder().decode([WidgetLayout].self, from: data) else {
            // First launch — save the default
            savedLayouts = [activeLayout]
            saveSavedLayouts()
            return
        }
        savedLayouts = layouts
    }

    private func saveSavedLayouts() {
        let listFile = directory.appendingPathComponent("layouts-list.json")
        do {
            let data = try JSONEncoder().encode(savedLayouts)
            try data.write(to: listFile, options: .atomic)
        } catch {
            logger.error("Failed to save layouts list: \(error.localizedDescription)")
        }
    }
}
