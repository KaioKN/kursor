import Foundation

public final class ConfigStore {
    public static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kursor", isDirectory: true)
    }

    public let url: URL

    public init(url: URL = ConfigStore.supportDirectory.appendingPathComponent("config.json")) {
        self.url = url
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Missing file → defaults. Unreadable JSON is moved aside (never silently overwritten).
    public func load() -> KursorConfig {
        guard let data = try? Data(contentsOf: url) else { return KursorConfig() }
        do {
            return try JSONDecoder().decode(KursorConfig.self, from: data)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let broken = url.deletingLastPathComponent().appendingPathComponent("config.broken-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: broken)
            return KursorConfig()
        }
    }

    public func save(_ config: KursorConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
