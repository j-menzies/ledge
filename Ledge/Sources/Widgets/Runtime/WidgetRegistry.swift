import SwiftUI
import Combine
import os.log

/// Manages registration and instantiation of widget types.
///
/// Built-in widgets are registered at app startup. Plugin widgets (future)
/// will be discovered and registered from .ledgewidget bundles.
class WidgetRegistry: ObservableObject {

    static let shared = WidgetRegistry()

    private let logger = Logger(subsystem: "com.ledge.app", category: "WidgetRegistry")

    /// All registered widget types, keyed by type ID.
    @Published private(set) var registeredTypes: [String: WidgetDescriptor] = [:]

    private init() {}

    /// Register a widget descriptor.
    func register(_ descriptor: WidgetDescriptor) {
        registeredTypes[descriptor.typeID] = descriptor
        logger.info("Registered widget: \(descriptor.displayName) (\(descriptor.typeID))")
    }

    /// Create a view for a widget type by its ID.
    func createWidgetView(typeID: String) -> AnyView? {
        guard let descriptor = registeredTypes[typeID] else {
            logger.error("Unknown widget type: \(typeID)")
            return nil
        }
        return descriptor.viewFactory()
    }

    /// All registered widget types as a sorted array.
    var allTypes: [WidgetDescriptor] {
        registeredTypes.values.sorted { $0.displayName < $1.displayName }
    }

    /// Register all built-in widgets. Called once at app startup.
    func registerBuiltInWidgets() {
        register(ClockWidget.descriptor)
        // TODO: Phase 1 — register more widgets:
        // register(CPUWidget.descriptor)
        // register(NowPlayingWidget.descriptor)
        logger.info("Registered \(self.registeredTypes.count) built-in widget(s)")
    }
}
