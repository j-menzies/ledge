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

    /// Default layout for the Xeneon Edge (2560x720).
    /// A 10-column by 3-row grid with 6 widgets.
    static let defaultLayout = WidgetLayout(
        id: UUID(),
        name: "Default",
        columns: 10,
        rows: 3,
        placements: [
            // Row 0-1: DateTime (2x2), Spotify (4x2), Calendar (3x2)
            WidgetPlacement(
                id: UUID(),
                widgetTypeID: "com.ledge.datetime",
                column: 0,
                row: 0,
                columnSpan: 2,
                rowSpan: 2,
                configuration: nil
            ),
            WidgetPlacement(
                id: UUID(),
                widgetTypeID: "com.ledge.spotify",
                column: 3,
                row: 0,
                columnSpan: 4,
                rowSpan: 2,
                configuration: nil
            ),
            WidgetPlacement(
                id: UUID(),
                widgetTypeID: "com.ledge.calendar",
                column: 7,
                row: 0,
                columnSpan: 3,
                rowSpan: 2,
                configuration: nil
            ),
            // Row 2: Weather (2x1), HomeAssistant (3x1), Web (3x1)
            WidgetPlacement(
                id: UUID(),
                widgetTypeID: "com.ledge.weather",
                column: 0,
                row: 2,
                columnSpan: 2,
                rowSpan: 1,
                configuration: nil
            ),
            WidgetPlacement(
                id: UUID(),
                widgetTypeID: "com.ledge.homeassistant",
                column: 3,
                row: 2,
                columnSpan: 3,
                rowSpan: 1,
                configuration: nil
            ),
            WidgetPlacement(
                id: UUID(),
                widgetTypeID: "com.ledge.web",
                column: 7,
                row: 2,
                columnSpan: 3,
                rowSpan: 1,
                configuration: nil
            ),
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
