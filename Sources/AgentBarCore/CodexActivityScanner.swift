import Foundation

public struct CodexActivityHourUsage: Equatable, Sendable {
    public let hour: Int
    public let minutes: Double

    public init(hour: Int, minutes: Double) {
        self.hour = hour
        self.minutes = minutes
    }
}

public struct CodexActivityUsageSnapshot: Equatable, Sendable {
    public let day: Date
    public let dayKey: String
    public let hours: [CodexActivityHourUsage]
    public let totalMinutes: Double
    public let maxHourlyMinutes: Double

    public init(day: Date, dayKey: String, hours: [CodexActivityHourUsage]) {
        self.day = day
        self.dayKey = dayKey
        self.hours = hours
        self.totalMinutes = hours.reduce(0) { $0 + $1.minutes }
        self.maxHourlyMinutes = hours.map(\.minutes).max() ?? 0
    }
}

public final class CodexActivityScanner: @unchecked Sendable {
    public static let activityGap: TimeInterval = 10 * 60

    private let sessionsRoot: URL
    private let calendar: Calendar

    public init(
        sessionsRoot: URL = CodexHome.url().appendingPathComponent("sessions", isDirectory: true),
        calendar: Calendar = .autoupdatingCurrent)
    {
        self.sessionsRoot = sessionsRoot
        self.calendar = calendar
    }

    public func hourlyActivityUsage(on date: Date = Date()) -> CodexActivityUsageSnapshot {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let dayKey = CodexCostScanner.dayKey(for: dayStart, calendar: calendar)
        let files = sessionFiles(since: dayStart, through: dayStart)
        let intervals = files.flatMap { parseActivityIntervals(in: $0, matching: dayKey) }
        let blocks = activeBlocks(from: intervals)
        let minutesByHour = distribute(blocks: blocks, dayStart: dayStart, dayEnd: dayEnd)
        let hours = (0..<24).map { hour in
            CodexActivityHourUsage(hour: hour, minutes: minutesByHour[hour])
        }
        return CodexActivityUsageSnapshot(day: dayStart, dayKey: dayKey, hours: hours)
    }

    private func activeBlocks(from intervals: [ActivityInterval]) -> [ActivityInterval] {
        let sorted = intervals.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }
        guard var current = sorted.first else { return [] }

        var blocks: [ActivityInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start.timeIntervalSince(current.end) <= Self.activityGap {
                current = ActivityInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                blocks.append(current)
                current = interval
            }
        }
        blocks.append(current)
        return blocks
    }

    private func distribute(blocks: [ActivityInterval], dayStart: Date, dayEnd: Date) -> [Double] {
        var minutes = Array(repeating: Double(0), count: 24)
        for block in blocks {
            let start = max(block.start, dayStart)
            let end = min(block.end, dayEnd)
            guard end > start else { continue }

            for hour in 0..<24 {
                guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart),
                      let hourEnd = calendar.date(byAdding: .hour, value: hour + 1, to: dayStart)
                else { continue }
                let overlapStart = max(start, hourStart)
                let overlapEnd = min(end, hourEnd)
                guard overlapEnd > overlapStart else { continue }
                minutes[hour] += overlapEnd.timeIntervalSince(overlapStart) / 60
            }
        }
        return minutes
    }

    private func parseActivityIntervals(in fileURL: URL, matching dayKey: String) -> [ActivityInterval] {
        var intervals: [ActivityInterval] = []

        CodexActivityLineScanner.scan(fileURL: fileURL) { data in
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  isActivityLine(obj),
                  let timestamp = obj["timestamp"] as? String,
                  let date = CodexCostScanner.parseTimestamp(timestamp),
                  CodexCostScanner.dayKey(for: date, calendar: calendar) == dayKey
            else { return }

            let duration = activityDuration(in: obj)
            let start = duration.map { max(0, $0) }.map { date.addingTimeInterval(-$0) } ?? date
            intervals.append(ActivityInterval(start: start, end: date))
        }

        return intervals
    }

    private func isActivityLine(_ obj: [String: Any]) -> Bool {
        guard let type = obj["type"] as? String else { return false }
        if type == "response_item" {
            return responseItemRole(in: obj) == "user"
        }
        guard type == "event_msg",
              let payload = obj["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String
        else { return false }

        if payloadType == "token_count" || payloadType == "user_message" || payloadType == "turn_diff" {
            return true
        }
        if payloadType.hasPrefix("exec_command_") || payloadType.hasPrefix("patch_apply_") {
            return true
        }
        if payloadType.hasPrefix("collab_") {
            return true
        }
        return false
    }

    private func responseItemRole(in obj: [String: Any]) -> String? {
        if let payload = obj["payload"] as? [String: Any],
           let item = payload["item"] as? [String: Any],
           let role = item["role"] as? String
        {
            return role
        }
        if let item = obj["item"] as? [String: Any],
           let role = item["role"] as? String
        {
            return role
        }
        if let role = obj["role"] as? String {
            return role
        }
        return nil
    }

    private func activityDuration(in obj: [String: Any]) -> TimeInterval? {
        guard let payload = obj["payload"] as? [String: Any] else { return nil }
        if let duration = payload["duration"] as? NSNumber {
            return duration.doubleValue
        }
        if let duration = payload["duration"] as? String, let value = Double(duration) {
            return value
        }
        if let durationMS = payload["duration_ms"] as? NSNumber {
            return durationMS.doubleValue / 1000
        }
        if let durationMS = payload["duration_ms"] as? String, let value = Double(durationMS) {
            return value / 1000
        }
        return nil
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
}

private struct ActivityInterval: Equatable {
    let start: Date
    let end: Date
}

private enum CodexActivityLineScanner {
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
