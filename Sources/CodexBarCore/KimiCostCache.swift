import Foundation

enum KimiCostCacheIO {
    /// Artifact schema version. Bump when the cache layout or parsing semantics change.
    private static let artifactVersion = 1

    private static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CodexBar", isDirectory: true)
    }

    static func cacheFileURL(cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? self.defaultCacheRoot()
        return root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("kimi-v\(Self.artifactVersion).json", isDirectory: false)
    }

    static func load(cacheRoot: URL? = nil) -> KimiCostCache {
        let url = self.cacheFileURL(cacheRoot: cacheRoot)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(KimiCostCache.self, from: data),
              decoded.version == Self.artifactVersion
        else {
            return KimiCostCache(version: Self.artifactVersion)
        }
        return decoded
    }

    static func save(cache: KimiCostCache, cacheRoot: URL? = nil) {
        let url = self.cacheFileURL(cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json", isDirectory: false)
        let data = (try? JSONEncoder().encode(cache)) ?? Data()
        do {
            try data.write(to: tmp, options: [.atomic])
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}

struct KimiCostCache: Codable {
    var version: Int
    var lastScanUnixMs: Int64 = 0
    var files: [String: KimiFileUsage] = [:]

    init(version: Int = 1) {
        self.version = version
    }
}

struct KimiFileUsage: Codable {
    var mtimeUnixMs: Int64
    var size: Int64
    /// Aggregated usage by local day key (`yyyy-MM-dd`) then normalized model name.
    var contributions: [String: [String: KimiPackedUsage]]
}

struct KimiPackedUsage: Codable, Equatable {
    /// Non-cached input tokens (wire field `inputOther`).
    var inputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var outputTokens: Int = 0
    var requestCount: Int = 0

    var totalTokens: Int {
        self.inputTokens + self.cacheReadTokens + self.cacheCreationTokens + self.outputTokens
    }
}
