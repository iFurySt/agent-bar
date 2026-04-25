import Foundation

public final class AgentBarCacheStore: @unchecked Sendable {
    public static let `default` = AgentBarCacheStore()

    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL = AgentBarCacheStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() -> AgentBarCache {
        lock.withLock {
            loadUnlocked()
        }
    }

    func update(_ mutate: (inout AgentBarCache) -> Void) {
        lock.withLock {
            var cache = loadUnlocked()
            mutate(&cache)
            saveUnlocked(cache)
        }
    }

    public func save(snapshot: AgentBarSnapshot, at date: Date = Date()) {
        update { cache in
            cache.latestSnapshot = CachedAgentBarSnapshot(snapshot: snapshot, updatedAt: date)
        }
    }

    public static func defaultFileURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let home = env["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".agentbar", isDirectory: true)
            .appendingPathComponent("cache.json", isDirectory: false)
    }

    private func loadUnlocked() -> AgentBarCache {
        guard let data = try? Data(contentsOf: fileURL),
              let cache = try? JSONDecoder().decode(AgentBarCache.self, from: data),
              cache.version == AgentBarCache.currentVersion
        else { return .empty }
        return cache
    }

    private func saveUnlocked(_ cache: AgentBarCache) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(cache)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Cache is an optimization; the app should keep working if persistence fails.
        }
    }
}

public struct AgentBarCache: Codable, Equatable, Sendable {
    static let currentVersion = 2
    static let empty = AgentBarCache(version: currentVersion)

    var version: Int = currentVersion
    var latestSnapshot: CachedAgentBarSnapshot?
    var rateLimitFiles: [String: CachedRateLimitFile] = [:]
    var costFiles: [String: CachedCostFile] = [:]
}

struct CachedAgentBarSnapshot: Codable, Equatable, Sendable {
    let rateLimits: CodexRateLimitSnapshot
    let costs: CodexCostSnapshot
    let accounts: [CodexAccountUsageSnapshot]
    let updatedAt: Date

    init(snapshot: AgentBarSnapshot, updatedAt: Date) {
        self.rateLimits = snapshot.rateLimits
        self.costs = snapshot.costs
        self.accounts = snapshot.accounts
        self.updatedAt = updatedAt
    }

    var snapshot: AgentBarSnapshot {
        AgentBarSnapshot(rateLimits: rateLimits, costs: costs, accounts: accounts)
    }
}

struct CachedFileMetadata: Codable, Equatable, Sendable {
    let size: UInt64
    let modifiedAt: TimeInterval

    init?(fileURL: URL) {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modified = values.contentModificationDate
        else { return nil }
        self.size = UInt64(max(0, size))
        self.modifiedAt = modified.timeIntervalSince1970
    }
}

struct CachedRateLimitFile: Codable, Equatable, Sendable {
    let metadata: CachedFileMetadata
    let candidate: CachedRateLimitCandidate?
}

struct CachedRateLimitCandidate: Codable, Equatable, Sendable {
    let timestamp: String
    let isBaseCodexLimit: Bool
    let primary: Int?
    let secondary: Int?
}

struct CachedCostFile: Codable, Equatable, Sendable {
    let metadata: CachedFileMetadata
    let days: [String: [String: TokenTotals]]
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
