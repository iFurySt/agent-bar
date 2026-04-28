import Foundation

public struct CodexCostSnapshot: Codable, Equatable, Sendable {
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

public struct CodexDailyTokenUsage: Equatable, Sendable {
    public let day: Date
    public let dayKey: String
    public let tokens: Int
    public let costUSD: Double

    public init(day: Date, dayKey: String, tokens: Int, costUSD: Double) {
        self.day = day
        self.dayKey = dayKey
        self.tokens = tokens
        self.costUSD = costUSD
    }
}

public struct CodexDailyTokenUsageSnapshot: Equatable, Sendable {
    public let days: [CodexDailyTokenUsage]
    public let totalTokens: Int
    public let maxDailyTokens: Int

    public init(days: [CodexDailyTokenUsage]) {
        self.days = days
        self.totalTokens = days.reduce(0) { $0 + $1.tokens }
        self.maxDailyTokens = days.map(\.tokens).max() ?? 0
    }
}

public struct CodexHourlyModelTokenUsage: Equatable, Sendable {
    public let model: String
    public let tokens: Int
    public let costUSD: Double

    public init(model: String, tokens: Int, costUSD: Double) {
        self.model = model
        self.tokens = tokens
        self.costUSD = costUSD
    }
}

public struct CodexHourlyTokenUsage: Equatable, Sendable {
    public let hour: Int
    public let models: [CodexHourlyModelTokenUsage]
    public let totalTokens: Int
    public let costUSD: Double

    public init(hour: Int, models: [CodexHourlyModelTokenUsage]) {
        self.hour = hour
        self.models = models
        self.totalTokens = models.reduce(0) { $0 + $1.tokens }
        self.costUSD = models.reduce(0) { $0 + $1.costUSD }
    }
}

public struct CodexHourlyTokenUsageSnapshot: Equatable, Sendable {
    public let day: Date
    public let dayKey: String
    public let hours: [CodexHourlyTokenUsage]
    public let totalTokens: Int
    public let maxHourlyTokens: Int

    public init(day: Date, dayKey: String, hours: [CodexHourlyTokenUsage]) {
        self.day = day
        self.dayKey = dayKey
        self.hours = hours
        self.totalTokens = hours.reduce(0) { $0 + $1.totalTokens }
        self.maxHourlyTokens = hours.map(\.totalTokens).max() ?? 0
    }
}

public final class CodexCostScanner: @unchecked Sendable {
    private let sessionsRoot: URL
    private let calendar: Calendar
    private let cacheStore: AgentBarCacheStore?

    public init(
        sessionsRoot: URL = CodexHome.url().appendingPathComponent("sessions", isDirectory: true),
        calendar: Calendar = .autoupdatingCurrent,
        cacheStore: AgentBarCacheStore? = .default)
    {
        self.sessionsRoot = sessionsRoot
        self.calendar = calendar
        self.cacheStore = cacheStore
    }

    public func scan(now: Date = Date()) -> CodexCostSnapshot {
        let todayKey = Self.dayKey(for: now, calendar: calendar)
        let since = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let sinceKey = Self.dayKey(for: since, calendar: calendar)
        let files = sessionFiles(since: since, through: now)
        let days = scanDays(files: files, sinceKey: sinceKey, todayKey: todayKey)

        let today = days[todayKey] ?? .zero
        var last30 = TokenTotals.zero
        for (_, totals) in days {
            last30.add(totals)
        }

        let snapshot = CodexCostSnapshot(
            todayCostUSD: today.costUSD,
            todayTokens: today.totalTokens,
            last30DaysCostUSD: last30.costUSD,
            last30DaysTokens: last30.totalTokens)

        return snapshot
    }

    public func dailyTokenUsage(days count: Int = 371, now: Date = Date()) -> CodexDailyTokenUsageSnapshot {
        let dayCount = max(1, count)
        let todayStart = calendar.startOfDay(for: now)
        let since = calendar.date(byAdding: .day, value: -(dayCount - 1), to: todayStart) ?? todayStart
        let sinceKey = Self.dayKey(for: since, calendar: calendar)
        let todayKey = Self.dayKey(for: todayStart, calendar: calendar)
        let files = sessionFiles(since: since, through: now)
        let totalsByDay = scanDays(files: files, sinceKey: sinceKey, todayKey: todayKey)

        var entries: [CodexDailyTokenUsage] = []
        var day = since
        while day <= todayStart {
            let key = Self.dayKey(for: day, calendar: calendar)
            let totals = totalsByDay[key] ?? .zero
            entries.append(CodexDailyTokenUsage(
                day: day,
                dayKey: key,
                tokens: totals.totalTokens,
                costUSD: totals.costUSD))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return CodexDailyTokenUsageSnapshot(days: entries)
    }

    public func yearlyTokenUsage(year: Int, now: Date = Date()) -> CodexDailyTokenUsageSnapshot {
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1
        var endComponents = DateComponents()
        endComponents.year = year
        endComponents.month = 12
        endComponents.day = 31

        guard let yearStart = calendar.date(from: startComponents),
              let yearEnd = calendar.date(from: endComponents)
        else {
            return CodexDailyTokenUsageSnapshot(days: [])
        }

        let sinceKey = Self.dayKey(for: yearStart, calendar: calendar)
        let untilKey = Self.dayKey(for: yearEnd, calendar: calendar)
        let files = sessionFiles(since: yearStart, through: yearEnd)
        let totalsByDay = scanDays(files: files, sinceKey: sinceKey, todayKey: untilKey)

        var entries: [CodexDailyTokenUsage] = []
        var day = yearStart
        while day <= yearEnd {
            let key = Self.dayKey(for: day, calendar: calendar)
            let totals = totalsByDay[key] ?? .zero
            entries.append(CodexDailyTokenUsage(
                day: day,
                dayKey: key,
                tokens: totals.totalTokens,
                costUSD: totals.costUSD))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return CodexDailyTokenUsageSnapshot(days: entries)
    }

    public func hourlyTokenUsage(on date: Date = Date()) -> CodexHourlyTokenUsageSnapshot {
        let dayStart = calendar.startOfDay(for: date)
        let dayKey = Self.dayKey(for: dayStart, calendar: calendar)
        let files = sessionFiles(since: dayStart, through: dayStart)
        let totalsByHour = scanHours(files: files, dayKey: dayKey)
        let modelOrder = ["gpt-5.5", "gpt-5.4", "claude-3.7-sonnet", "gemini-1.5-pro"]

        let hours = (0..<24).map { hour in
            let hourKey = Self.hourKey(hour)
            let models = totalsByHour[hourKey] ?? [:]
            let entries = models
                .map { model, totals in
                    CodexHourlyModelTokenUsage(model: model, tokens: totals.totalTokens, costUSD: totals.costUSD)
                }
                .sorted { lhs, rhs in
                    let leftIndex = modelOrder.firstIndex(of: lhs.model) ?? modelOrder.count
                    let rightIndex = modelOrder.firstIndex(of: rhs.model) ?? modelOrder.count
                    if leftIndex != rightIndex { return leftIndex < rightIndex }
                    return lhs.model < rhs.model
                }
            return CodexHourlyTokenUsage(hour: hour, models: entries)
        }

        return CodexHourlyTokenUsageSnapshot(day: dayStart, dayKey: dayKey, hours: hours)
    }

    public func usageYearRange(now: Date = Date()) -> ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: now)
        var years = Set([currentYear])

        if let cache = cacheStore?.load() {
            for file in cache.costFiles.values {
                for (day, models) in file.days {
                    let hasTokens = models.values.contains { $0.totalTokens > 0 }
                    if hasTokens, let year = Int(day.prefix(4)) {
                        years.insert(year)
                    }
                }
            }
        }

        if let items = try? FileManager.default.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        {
            for item in items {
                guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey]),
                      values.isDirectory == true,
                      let year = Int(item.lastPathComponent)
                else { continue }
                years.insert(year)
            }
        }

        let boundedYears = years.filter { $0 <= currentYear }
        return (boundedYears.min() ?? currentYear)...currentYear
    }

    private func scanDays(files: [URL], sinceKey: String, todayKey: String) -> [String: TokenTotals] {
        let cache = cacheStore?.load() ?? .empty
        var updatedFiles: [String: CachedCostFile] = [:]
        var days: [String: TokenTotals] = [:]
        let timeZoneIdentifier = calendar.timeZone.identifier

        for file in files {
            guard let metadata = CachedFileMetadata(fileURL: file) else { continue }
            let fileDays: [String: [String: TokenTotals]]
            if let cached = cache.costFiles[file.path],
               cached.metadata == metadata,
               cached.timeZoneIdentifier == timeZoneIdentifier,
               !cached.needsPricingRefresh
            {
                fileDays = cached.days
                updatedFiles[file.path] = cached
            } else {
                let parsed = parseFile(file)
                fileDays = parsed.days
                updatedFiles[file.path] = CachedCostFile(
                    metadata: metadata,
                    days: parsed.days,
                    hours: parsed.hours,
                    timeZoneIdentifier: timeZoneIdentifier)
            }

            for (day, models) in fileDays where day >= sinceKey && day <= todayKey {
                for (model, totals) in models {
                    days[day, default: .zero].add(totals: totals, model: model)
                }
            }
        }

        cacheStore?.update { cache in
            for (path, file) in updatedFiles {
                cache.costFiles[path] = file
            }
        }

        return days
    }

    private func scanHours(files: [URL], dayKey: String) -> [String: [String: TokenTotals]] {
        let cache = cacheStore?.load() ?? .empty
        var updatedFiles: [String: CachedCostFile] = [:]
        var hours: [String: [String: TokenTotals]] = [:]
        let timeZoneIdentifier = calendar.timeZone.identifier

        for file in files {
            guard let metadata = CachedFileMetadata(fileURL: file) else { continue }
            let fileHours: [String: [String: [String: TokenTotals]]]
            if let cached = cache.costFiles[file.path],
               cached.metadata == metadata,
               cached.timeZoneIdentifier == timeZoneIdentifier,
               !cached.needsPricingRefresh,
               let cachedHours = cached.hours
            {
                fileHours = cachedHours
                updatedFiles[file.path] = cached
            } else {
                let parsed = parseFile(file)
                fileHours = parsed.hours
                updatedFiles[file.path] = CachedCostFile(
                    metadata: metadata,
                    days: parsed.days,
                    hours: parsed.hours,
                    timeZoneIdentifier: timeZoneIdentifier)
            }

            for (hour, models) in fileHours[dayKey] ?? [:] {
                for (model, totals) in models {
                    hours[hour, default: [:]][model, default: .zero].add(totals: totals, model: model)
                }
            }
        }

        cacheStore?.update { cache in
            for (path, file) in updatedFiles {
                cache.costFiles[path] = file
            }
        }

        return hours
    }

    private func sessionFiles(since: Date, through now: Date) -> [URL] {
        var files: [URL] = []
        var seenPaths: Set<String> = []

        func append(_ candidates: [URL]) {
            for file in candidates where !seenPaths.contains(file.path) {
                seenPaths.insert(file.path)
                files.append(file)
            }
        }

        var day = calendar.startOfDay(for: since)
        let end = calendar.startOfDay(for: now)

        while day <= end {
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            if let year = components.year, let month = components.month, let dateDay = components.day {
                let dir = sessionsRoot
                    .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                    .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                    .appendingPathComponent(String(format: "%02d", dateDay), isDirectory: true)
                append(jsonlFiles(in: dir))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        append(recentlyModifiedJsonlFiles(modifiedSince: since))
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

    private func recentlyModifiedJsonlFiles(modifiedSince since: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "jsonl" {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= since
            else { continue }
            files.append(fileURL)
        }
        return files
    }

    private func parseFile(_ fileURL: URL) -> ParsedCostFile {
        var currentModel = "gpt-5"
        var previousTotals: RawTokenTotals?
        var days: [String: [String: TokenTotals]] = [:]
        var hours: [String: [String: [String: TokenTotals]]] = [:]

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
            let hourKey = Self.hourKey(calendar.component(.hour, from: date))
            days[dayKey, default: [:]][normalizedModel, default: .zero].add(raw: clampedDelta, model: normalizedModel)
            hours[dayKey, default: [:]][hourKey, default: [:]][normalizedModel, default: .zero].add(
                raw: clampedDelta,
                model: normalizedModel)
        }

        return ParsedCostFile(days: days, hours: hours)
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

    static func hourKey(_ hour: Int) -> String {
        String(format: "%02d", max(0, min(23, hour)))
    }
}

private struct ParsedCostFile {
    let days: [String: [String: TokenTotals]]
    let hours: [String: [String: [String: TokenTotals]]]
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

struct TokenTotals: Codable, Equatable, Sendable {
    var totalTokens: Int
    var costUSD: Double

    static let zero = TokenTotals(totalTokens: 0, costUSD: 0)

    fileprivate mutating func add(raw: RawTokenTotals, model: String) {
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
