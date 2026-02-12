import SwiftUI

/// The size of a widget in grid cells.
struct GridSize: Codable, Equatable, Sendable {
    let columns: Int
    let rows: Int

    static let oneByOne = GridSize(columns: 1, rows: 1)
    static let twoByOne = GridSize(columns: 2, rows: 1)
    static let twoByTwo = GridSize(columns: 2, rows: 2)
    static let threeByOne = GridSize(columns: 3, rows: 1)
    static let threeByTwo = GridSize(columns: 3, rows: 2)
    static let threeByThree = GridSize(columns: 3, rows: 3)
    static let fourByOne = GridSize(columns: 4, rows: 1)
    static let fourByTwo = GridSize(columns: 4, rows: 2)
    static let fourByThree = GridSize(columns: 4, rows: 3)
    static let fiveByThree = GridSize(columns: 5, rows: 3)
    static let tenByThree = GridSize(columns: 10, rows: 3)
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
