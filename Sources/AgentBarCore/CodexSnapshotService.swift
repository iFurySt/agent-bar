import Foundation

public struct AgentBarSnapshot: Equatable, Sendable {
    public let rateLimits: CodexRateLimitSnapshot
    public let costs: CodexCostSnapshot
    public let isUsingRateLimitFallback: Bool

    public init(
        rateLimits: CodexRateLimitSnapshot,
        costs: CodexCostSnapshot,
        isUsingRateLimitFallback: Bool = false)
    {
        self.rateLimits = rateLimits
        self.costs = costs
        self.isUsingRateLimitFallback = isUsingRateLimitFallback
    }
}

public final class CodexSnapshotService: @unchecked Sendable {
    private let usageClient: CodexUsageClient
    private let costScanner: CodexCostScanner
    private let fallbackScanner: CodexRateLimitFallbackScanner
    private let cacheStore: AgentBarCacheStore

    public init(
        usageClient: CodexUsageClient = CodexUsageClient(),
        costScanner: CodexCostScanner? = nil,
        fallbackScanner: CodexRateLimitFallbackScanner? = nil,
        cacheStore: AgentBarCacheStore = .default)
    {
        self.usageClient = usageClient
        self.costScanner = costScanner ?? CodexCostScanner(cacheStore: cacheStore)
        self.fallbackScanner = fallbackScanner ?? CodexRateLimitFallbackScanner(cacheStore: cacheStore)
        self.cacheStore = cacheStore
    }

    public func cachedSnapshot() -> AgentBarSnapshot? {
        cacheStore.load().latestSnapshot?.snapshot
    }

    public func snapshot() async -> AgentBarSnapshot {
        let costScanner = self.costScanner
        let costTask = Task.detached(priority: .utility) {
            costScanner.scan()
        }

        let resolvedRateLimits = await resolveRateLimits()
        let snapshot = await AgentBarSnapshot(
            rateLimits: resolvedRateLimits.snapshot,
            costs: costTask.value,
            isUsingRateLimitFallback: resolvedRateLimits.isUsingFallback)
        cacheStore.save(snapshot: snapshot)
        return snapshot
    }

    public func quickRateLimits() async -> CodexRateLimitSnapshot {
        await resolveRateLimits().snapshot
    }

    private func resolveRateLimits() async -> (snapshot: CodexRateLimitSnapshot, isUsingFallback: Bool) {
        let fallbackScanner = self.fallbackScanner
        let fallbackTask = Task.detached(priority: .utility) {
            fallbackScanner.latestRateLimits()
        }

        let fallbackRateLimits = await fallbackTask.value
        if !fallbackRateLimits.hasMissingPercent {
            return (fallbackRateLimits, true)
        }

        do {
            let fetchedRateLimits = try await usageClient.fetchRateLimits()
            let rateLimits = fetchedRateLimits.fillingMissing(with: fallbackRateLimits)
            return (
                rateLimits,
                fetchedRateLimits.hasMissingPercent && fallbackRateLimits != fetchedRateLimits)
        } catch {
            return (fallbackRateLimits, true)
        }
    }
}

public final class CodexRateLimitFallbackScanner: @unchecked Sendable {
    private let sessionsRoot: URL
    private let cacheStore: AgentBarCacheStore?

    public init(
        sessionsRoot: URL = CodexHome.url().appendingPathComponent("sessions", isDirectory: true),
        cacheStore: AgentBarCacheStore? = .default)
    {
        self.sessionsRoot = sessionsRoot
        self.cacheStore = cacheStore
    }

    public func latestRateLimits() -> CodexRateLimitSnapshot {
        let files = recentFiles()
        let currentPaths = Set(files.map(\.path))
        let cache = cacheStore?.load() ?? .empty
        var updatedFiles: [String: CachedRateLimitFile] = [:]
        var best: RateLimitCandidate?

        for file in files {
            guard let metadata = CachedFileMetadata(fileURL: file) else { continue }
            if let cached = cache.rateLimitFiles[file.path], cached.metadata == metadata {
                updatedFiles[file.path] = cached
                if let candidate = cached.candidate?.rateLimitCandidate,
                   Self.shouldReplace(best: best, with: candidate)
                {
                    best = candidate
                }
                continue
            }

            var fileBest: RateLimitCandidate?
            JSONLLineScannerForRates.scan(fileURL: file) { data in
                guard data.containsAscii(#""token_count""#),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      obj["type"] as? String == "event_msg",
                      let timestamp = obj["timestamp"] as? String
                else { return true }

                let payload = obj["payload"] as? [String: Any]
                guard payload?["type"] as? String == "token_count",
                      let rateLimits = payload?["rate_limits"] as? [String: Any]
                else { return true }

                let candidate = RateLimitCandidate(
                    timestamp: timestamp,
                    isBaseCodexLimit: Self.isBaseCodexLimit(rateLimits["limit_id"]),
                    primary: Self.remainingPercent(rateLimits["primary"]),
                    secondary: Self.remainingPercent(rateLimits["secondary"]))
                guard candidate.primary != nil || candidate.secondary != nil else { return true }

                if Self.shouldReplace(best: fileBest, with: candidate) {
                    fileBest = candidate
                }
                if Self.shouldReplace(best: best, with: candidate) {
                    best = candidate
                }

                // The scanner walks newest lines first; once the base Codex quota
                // is found in this file, older lines in the same file cannot beat it.
                return !candidate.isBaseCodexLimit
            }

            updatedFiles[file.path] = CachedRateLimitFile(
                metadata: metadata,
                candidate: fileBest.map(CachedRateLimitCandidate.init))
        }

        let snapshot = CodexRateLimitSnapshot(
            fiveHourRemainingPercent: best?.primary,
            weeklyRemainingPercent: best?.secondary)

        cacheStore?.update { cache in
            cache.rateLimitFiles = cache.rateLimitFiles.filter { currentPaths.contains($0.key) }
            for (path, file) in updatedFiles {
                cache.rateLimitFiles[path] = file
            }
        }

        return snapshot
    }

    private func recentFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        let cutoff = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  let modified = values?.contentModificationDate,
                  modified >= cutoff
            else { continue }
            files.append((url, modified))
        }

        return files.sorted { $0.1 > $1.1 }.prefix(80).map(\.0)
    }

    private static func remainingPercent(_ raw: Any?) -> Int? {
        guard let dictionary = raw as? [String: Any],
              let used = dictionary["used_percent"] as? NSNumber
        else { return nil }
        return min(100, max(0, Int((100 - used.doubleValue).rounded())))
    }

    private static func isBaseCodexLimit(_ raw: Any?) -> Bool {
        guard let limitID = raw as? String, !limitID.isEmpty else { return true }
        return limitID == "codex"
    }

    private static func shouldReplace(best: RateLimitCandidate?, with candidate: RateLimitCandidate) -> Bool {
        guard let best else { return true }
        if candidate.isBaseCodexLimit != best.isBaseCodexLimit {
            return candidate.isBaseCodexLimit
        }
        return candidate.timestamp > best.timestamp
    }
}

private struct RateLimitCandidate {
    let timestamp: String
    let isBaseCodexLimit: Bool
    let primary: Int?
    let secondary: Int?
}

private extension CachedRateLimitCandidate {
    init(_ candidate: RateLimitCandidate) {
        self.init(
            timestamp: candidate.timestamp,
            isBaseCodexLimit: candidate.isBaseCodexLimit,
            primary: candidate.primary,
            secondary: candidate.secondary)
    }

    var rateLimitCandidate: RateLimitCandidate {
        RateLimitCandidate(
            timestamp: timestamp,
            isBaseCodexLimit: isBaseCodexLimit,
            primary: primary,
            secondary: secondary)
    }
}

private enum JSONLLineScannerForRates {
    static func scan(fileURL: URL, onLine: (Data) -> Bool) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        let newline = Data([0x0A])
        let chunkSize = 64 * 1024
        let fileSize = (try? handle.seekToEnd()) ?? 0
        var offset = fileSize
        var remainder = Data()

        while offset > 0 {
            let readSize = min(chunkSize, Int(offset))
            offset -= UInt64(readSize)
            guard (try? handle.seek(toOffset: offset)) != nil,
                  var chunk = try? handle.read(upToCount: readSize),
                  !chunk.isEmpty
            else { break }

            chunk.append(remainder)
            var searchEnd = chunk.endIndex
            while let range = chunk.range(of: newline, options: .backwards, in: chunk.startIndex..<searchEnd) {
                let line = chunk.subdata(in: range.upperBound..<searchEnd)
                searchEnd = range.lowerBound
                if !line.isEmpty, !onLine(line) {
                    return
                }
            }

            remainder = chunk.subdata(in: chunk.startIndex..<searchEnd)
        }

        if !remainder.isEmpty {
            _ = onLine(remainder)
        }
    }
}

private extension Data {
    func containsAscii(_ text: String) -> Bool {
        guard let needle = text.data(using: .utf8) else { return false }
        return range(of: needle) != nil
    }
}
