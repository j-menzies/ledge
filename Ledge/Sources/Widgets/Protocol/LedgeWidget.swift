import SwiftUI

/// The size of a widget in grid cells.
struct GridSize: Codable, Equatable, Sendable {
    let columns: Int
    let rows: Int

    // Small
    static let oneByOne = GridSize(columns: 1, rows: 1)
    static let twoByOne = GridSize(columns: 2, rows: 1)
    static let twoByTwo = GridSize(columns: 2, rows: 2)
    static let twoByThree = GridSize(columns: 2, rows: 3)
    static let threeByOne = GridSize(columns: 3, rows: 1)
    static let threeByTwo = GridSize(columns: 3, rows: 2)
    static let threeByThree = GridSize(columns: 3, rows: 3)
    // Medium
    static let fourByOne = GridSize(columns: 4, rows: 1)
    static let fourByTwo = GridSize(columns: 4, rows: 2)
    static let fourByThree = GridSize(columns: 4, rows: 3)
    static let fourByFour = GridSize(columns: 4, rows: 4)
    static let fiveByTwo = GridSize(columns: 5, rows: 2)
    static let fiveByThree = GridSize(columns: 5, rows: 3)
    static let fiveByFour = GridSize(columns: 5, rows: 4)
    // Large
    static let sixByTwo = GridSize(columns: 6, rows: 2)
    static let sixByThree = GridSize(columns: 6, rows: 3)
    static let sixByFour = GridSize(columns: 6, rows: 4)
    static let sixBySix = GridSize(columns: 6, rows: 6)
    static let eightByFour = GridSize(columns: 8, rows: 4)
    static let eightBySix = GridSize(columns: 8, rows: 6)
    // Extra large
    static let tenByThree = GridSize(columns: 10, rows: 3)
    static let tenByFour = GridSize(columns: 10, rows: 4)
    static let tenBySix = GridSize(columns: 10, rows: 6)
    static let twelveBySix = GridSize(columns: 12, rows: 6)
    static let twentyBySix = GridSize(columns: 20, rows: 6)
}

/// Permissions that a widget may require.
/// Used to gate panel display — all permissions must be resolved before the panel renders.
enum WidgetPermission: String, Hashable, Sendable {
    case camera     // CoreMediaIO camera detection (SystemAudio)
    case location   // CoreLocation (Weather)
    case calendar   // EventKit calendar access (Calendar)
}

/// Metadata describing a widget type, used by the registry.
///
/// This is separated from the view itself to avoid associated type
/// complications. The registry stores these descriptors and uses
/// the `viewFactory` closure to create widget views on demand.
struct WidgetDescriptor {
    let typeID: String
    let displayName: String
    let description: String
    let iconSystemName: String
    let minimumSize: GridSize
    let defaultSize: GridSize
    let maximumSize: GridSize?
    let defaultConfiguration: Data?
    let viewFactory: (UUID, WidgetConfigStore) -> AnyView
    let settingsFactory: ((UUID, WidgetConfigStore) -> AnyView)?
    var requiredPermissions: Set<WidgetPermission> = []
}

/// Provides platform services to a widget instance.
///
/// Each widget receives its own context when loaded. The context provides
/// access to system data, persistent storage, and host services.
@Observable
class WidgetContext {

    /// The widget's current allocated size in points.
    var size: CGSize

    /// Unique ID for this widget instance (different from the widget type ID).
    let instanceID: UUID

    /// The shared config store for reading/writing widget configuration.
    let configStore: WidgetConfigStore

    init(instanceID: UUID, size: CGSize, configStore: WidgetConfigStore) {
        self.instanceID = instanceID
        self.size = size
        self.configStore = configStore
    }
}
