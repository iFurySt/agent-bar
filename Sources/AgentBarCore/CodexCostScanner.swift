import Foundation

public struct CodexCostSnapshot: Equatable, Sendable {
    public let todayCostUSD: Double
    public let todayTokens: Int
    public let last30DaysCostUSD: Double
    public let last30DaysTokens: Int

    public init(todayCostUSD: Double, todayTokens: Int, last30DaysCostUSD: Double, last30DaysTokens: Int) {
        self.todayCostUSD = todayCostUSD
        self.todayTokens = todayTokens
        self.last30DaysCostUSD = last30DaysCostUSD
        self.last30DaysTokens = last30DaysTokens
    }
}

public final class CodexCostScanner: @unchecked Sendable {
    private let sessionsRoot: URL
    private let calendar: Calendar

    public init(
        sessionsRoot: URL = CodexHome.url().appendingPathComponent("sessions", isDirectory: true),
        calendar: Calendar = .current)
    {
        self.sessionsRoot = sessionsRoot
        self.calendar = calendar
    }

    public func scan(now: Date = Date()) -> CodexCostSnapshot {
        let todayKey = Self.dayKey(for: now, calendar: calendar)
        let since = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let sinceKey = Self.dayKey(for: since, calendar: calendar)
        let files = sessionFiles(since: since, through: now)

        var days: [String: TokenTotals] = [:]
        for file in files {
            let fileDays = parseFile(file)
            for (day, models) in fileDays where day >= sinceKey && day <= todayKey {
                for (model, totals) in models {
                    days[day, default: .zero].add(totals: totals, model: model)
                }
            }
        }

        let today = days[todayKey] ?? .zero
        var last30 = TokenTotals.zero
        for (_, totals) in days {
            last30.add(totals)
        }

        return CodexCostSnapshot(
            todayCostUSD: today.costUSD,
            todayTokens: today.totalTokens,
            last30DaysCostUSD: last30.costUSD,
            last30DaysTokens: last30.totalTokens)
    }

    private func sessionFiles(since: Date, through now: Date) -> [URL] {
        var files: [URL] = []
        var day = calendar.startOfDay(for: since)
        let end = calendar.startOfDay(for: now)

        while day <= end {
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            if let year = components.year, let month = components.month, let dateDay = components.day {
                let dir = sessionsRoot
                    .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                    .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                    .appendingPathComponent(String(format: "%02d", dateDay), isDirectory: true)
                files.append(contentsOf: jsonlFiles(in: dir))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return files.sorted { $0.path < $1.path }
    }

    private func jsonlFiles(in directory: URL) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        return items.filter { $0.pathExtension.lowercased() == "jsonl" }
    }

    private func parseFile(_ fileURL: URL) -> [String: [String: TokenTotals]] {
        var currentModel = "gpt-5"
        var previousTotals: RawTokenTotals?
        var days: [String: [String: TokenTotals]] = [:]

        JSONLLineScanner.scan(fileURL: fileURL) { data in
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String
            else { return }

            if type == "turn_context" {
                if let payload = obj["payload"] as? [String: Any],
                   let model = payload["model"] as? String,
                   !model.isEmpty
                {
                    currentModel = model
                }
                return
            }

            guard type == "event_msg",
                  let payload = obj["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let timestamp = obj["timestamp"] as? String,
                  let date = Self.parseTimestamp(timestamp)
            else { return }

            let info = payload["info"] as? [String: Any]
            let model = (info?["model"] as? String)
                ?? (info?["model_name"] as? String)
                ?? (payload["model"] as? String)
                ?? currentModel

            let total = info?["total_token_usage"] as? [String: Any]
            let last = info?["last_token_usage"] as? [String: Any]

            let delta: RawTokenTotals
            if let total {
                let next = RawTokenTotals(dictionary: total)
                let previous = previousTotals ?? .zero
                delta = RawTokenTotals(
                    input: max(0, next.input - previous.input),
                    cached: max(0, next.cached - previous.cached),
                    output: max(0, next.output - previous.output))
                previousTotals = next
            } else if let last {
                delta = RawTokenTotals(dictionary: last)
                let previous = previousTotals ?? .zero
                previousTotals = RawTokenTotals(
                    input: previous.input + delta.input,
                    cached: previous.cached + delta.cached,
                    output: previous.output + delta.output)
            } else {
                return
            }

            guard delta.input > 0 || delta.output > 0 else { return }
            let normalizedModel = CodexPricing.normalizeCodexModel(model)
            let clampedDelta = RawTokenTotals(
                input: delta.input,
                cached: min(delta.cached, delta.input),
                output: delta.output)
            let dayKey = Self.dayKey(for: date, calendar: calendar)
            days[dayKey, default: [:]][normalizedModel, default: .zero].add(raw: clampedDelta, model: normalizedModel)
        }

        return days
    }

    static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

private struct RawTokenTotals {
    var input: Int
    var cached: Int
    var output: Int

    static let zero = RawTokenTotals(input: 0, cached: 0, output: 0)

    init(input: Int, cached: Int, output: Int) {
        self.input = input
        self.cached = cached
        self.output = output
    }

    init(dictionary: [String: Any]) {
        self.input = Self.int(dictionary["input_tokens"])
        self.cached = Self.int(dictionary["cached_input_tokens"] ?? dictionary["cache_read_input_tokens"])
        self.output = Self.int(dictionary["output_tokens"])
    }

    private static func int(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
}

private struct TokenTotals {
    var totalTokens: Int
    var costUSD: Double

    static let zero = TokenTotals(totalTokens: 0, costUSD: 0)

    mutating func add(raw: RawTokenTotals, model: String) {
        totalTokens += raw.input + raw.output
        costUSD += CodexPricing.codexCostUSD(
            model: model,
            inputTokens: raw.input,
            cachedInputTokens: raw.cached,
            outputTokens: raw.output) ?? 0
    }

    mutating func add(totals: TokenTotals, model _: String) {
        add(totals)
    }

    mutating func add(_ totals: TokenTotals) {
        totalTokens += totals.totalTokens
        costUSD += totals.costUSD
    }
}

private enum JSONLLineScanner {
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
