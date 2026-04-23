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

    public init(
        usageClient: CodexUsageClient = CodexUsageClient(),
        costScanner: CodexCostScanner = CodexCostScanner(),
        fallbackScanner: CodexRateLimitFallbackScanner = CodexRateLimitFallbackScanner())
    {
        self.usageClient = usageClient
        self.costScanner = costScanner
        self.fallbackScanner = fallbackScanner
    }

    public func snapshot() async -> AgentBarSnapshot {
        let costScanner = self.costScanner
        let costTask = Task.detached(priority: .utility) {
            costScanner.scan()
        }

        let resolvedRateLimits = await resolveRateLimits()
        return await AgentBarSnapshot(
            rateLimits: resolvedRateLimits.snapshot,
            costs: costTask.value,
            isUsingRateLimitFallback: resolvedRateLimits.isUsingFallback)
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

    public init(sessionsRoot: URL = CodexHome.url().appendingPathComponent("sessions", isDirectory: true)) {
        self.sessionsRoot = sessionsRoot
    }

    public func latestRateLimits() -> CodexRateLimitSnapshot {
        let files = recentFiles()
        var best: RateLimitCandidate?

        for file in files {
            JSONLLineScannerForRates.scan(fileURL: file) { data in
                guard data.containsAscii(#""token_count""#),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      obj["type"] as? String == "event_msg",
                      let timestamp = obj["timestamp"] as? String
                else { return }

                let payload = obj["payload"] as? [String: Any]
                guard payload?["type"] as? String == "token_count",
                      let rateLimits = payload?["rate_limits"] as? [String: Any]
                else { return }

                let candidate = RateLimitCandidate(
                    timestamp: timestamp,
                    isBaseCodexLimit: Self.isBaseCodexLimit(rateLimits["limit_id"]),
                    primary: Self.remainingPercent(rateLimits["primary"]),
                    secondary: Self.remainingPercent(rateLimits["secondary"]))
                guard candidate.primary != nil || candidate.secondary != nil else { return }

                if Self.shouldReplace(best: best, with: candidate) {
                    best = candidate
                }
            }
        }

        return CodexRateLimitSnapshot(
            fiveHourRemainingPercent: best?.primary,
            weeklyRemainingPercent: best?.secondary)
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

private enum JSONLLineScannerForRates {
    static func scan(fileURL: URL, onLine: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        let newline = Data([0x0A])
        var buffer = Data()
        while true {
            let chunk = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let range = buffer.range(of: newline) {
                let line = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)
                if !line.isEmpty {
                    onLine(line)
                }
            }
        }

        if !buffer.isEmpty {
            onLine(buffer)
        }
    }
}

private extension Data {
    func containsAscii(_ text: String) -> Bool {
        guard let needle = text.data(using: .utf8) else { return false }
        return range(of: needle) != nil
    }
}
