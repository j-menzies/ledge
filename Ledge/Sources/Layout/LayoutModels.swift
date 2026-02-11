import Foundation

/// A saved widget layout configuration.
///
/// Users can create multiple layouts (e.g., "Work", "Gaming", "Music")
/// and switch between them.
struct WidgetLayout: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var columns: Int
    var rows: Int
    var placements: [WidgetPlacement]

    /// Default layout for the Xeneon Edge (2560×720).
    /// A 6-column by 2-row grid gives roughly 426×360 per cell.
    static let defaultLayout = WidgetLayout(
        id: UUID(),
        name: "Default",
        columns: 6,
        rows: 2,
        placements: [
            WidgetPlacement(
                id: UUID(),
                widgetTypeID: "com.ledge.clock",
                column: 2,
                row: 0,
                columnSpan: 2,
                rowSpan: 2,
                configuration: nil
            )
        ]
    )
}

/// The placement of a single widget within a layout grid.
struct WidgetPlacement: Codable, Identifiable, Equatable {
    let id: UUID
    let widgetTypeID: String   // References a registered widget type
    var column: Int             // Grid column (0-based)
    var row: Int                // Grid row (0-based)
    var columnSpan: Int         // Width in grid cells
    var rowSpan: Int            // Height in grid cells
    var configuration: Data?    // Widget-specific config (JSON), optional
}
