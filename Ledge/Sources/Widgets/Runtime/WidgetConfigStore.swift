import Foundation
import Combine
import os.log

/// Persists per-widget-instance configuration as JSON files.
///
/// Each widget instance gets its own JSON file keyed by its UUID,
/// stored in `~/Library/Application Support/Ledge/widget-configs/`.
/// An in-memory cache avoids repeated disk reads.
///
/// Publishes `configDidChange` with the instanceID whenever config is written,
/// so dashboard widgets can reload in real time when settings change.
@Observable
class WidgetConfigStore {

    private let logger = Logger(subsystem: "com.ledge.app", category: "WidgetConfigStore")
    private let directory: URL
    private var cache: [UUID: Data] = [:]

    /// Emits the instanceID of a widget whose config was just written.
    /// Dashboard widgets subscribe to reload their config in real time.
    let configDidChange = PassthroughSubject<UUID, Never>()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("Ledge/widget-configs", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Read the configuration for a widget instance, decoded as the given type.
    func read<T: Decodable>(instanceID: UUID, as type: T.Type) -> T? {
        if let cached = cache[instanceID] {
            return try? JSONDecoder().decode(type, from: cached)
        }

        let fileURL = fileURL(for: instanceID)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        cache[instanceID] = data
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Write configuration for a widget instance.
    func write<T: Encodable>(instanceID: UUID, value: T) {
        guard let data = try? JSONEncoder().encode(value) else {
            logger.error("Failed to encode config for \(instanceID.uuidString)")
            return
        }

        cache[instanceID] = data

        let fileURL = fileURL(for: instanceID)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to write config for \(instanceID.uuidString): \(error.localizedDescription)")
        }

        // Notify dashboard widgets so they reload
        configDidChange.send(instanceID)
    }

    /// Read raw JSON Data for a widget instance (used by WidgetContainer).
    func readRaw(instanceID: UUID) -> Data? {
        if let cached = cache[instanceID] {
            return cached
        }
        let fileURL = fileURL(for: instanceID)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        cache[instanceID] = data
        return data
    }

    /// Remove configuration for a widget instance.
    func remove(instanceID: UUID) {
        cache.removeValue(forKey: instanceID)
        let fileURL = fileURL(for: instanceID)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func fileURL(for instanceID: UUID) -> URL {
        directory.appendingPathComponent("\(instanceID.uuidString).json")
    }
}
