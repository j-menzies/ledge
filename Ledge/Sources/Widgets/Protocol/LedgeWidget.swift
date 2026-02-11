import SwiftUI
import Combine

/// The size of a widget in grid cells.
struct GridSize: Codable, Equatable, Sendable {
    let columns: Int
    let rows: Int

    static let oneByOne = GridSize(columns: 1, rows: 1)
    static let twoByOne = GridSize(columns: 2, rows: 1)
    static let twoByTwo = GridSize(columns: 2, rows: 2)
    static let threeByOne = GridSize(columns: 3, rows: 1)
    static let fourByOne = GridSize(columns: 4, rows: 1)
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
    let minimumSize: GridSize
    let defaultSize: GridSize
    let maximumSize: GridSize?
    let viewFactory: () -> AnyView
    let settingsFactory: () -> AnyView
}

/// Provides platform services to a widget instance.
///
/// Each widget receives its own context when loaded. The context provides
/// access to system data, persistent storage, and host services.
@MainActor
class WidgetContext: ObservableObject {

    /// The widget's current allocated size in points.
    @Published var size: CGSize

    /// Unique ID for this widget instance (different from the widget type ID).
    let instanceID: UUID

    init(instanceID: UUID, size: CGSize) {
        self.instanceID = instanceID
        self.size = size
    }

    // TODO: Phase 1 — Add system data access, media access, storage, etc.
    // let systemData: SystemDataAccess
    // let media: MediaDataAccess
    // let storage: WidgetStorage
}
