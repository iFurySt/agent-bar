import XCTest
@testable import AgentBarCore

final class CodexCostScannerTests: XCTestCase {
    func testScansCodexTokenCountEvents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayDir = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("22", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        let file = dayDir.appendingPathComponent("rollout.jsonl")
        let lines = [
            #"{"timestamp":"2026-04-22T10:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-04-22T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100,"total_tokens":1100}}}}"#,
            #"{"timestamp":"2026-04-22T10:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1800,"cached_input_tokens":500,"output_tokens":150,"total_tokens":1950}}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanner = CodexCostScanner(
            sessionsRoot: root,
            calendar: calendar,
            cacheStore: AgentBarCacheStore(fileURL: root.appendingPathComponent("cache.json")))
        let now = CodexCostScanner.parseTimestamp("2026-04-22T12:00:00.000Z")!

        let snapshot = scanner.scan(now: now)

        XCTAssertEqual(snapshot.todayTokens, 1_950)
        XCTAssertEqual(snapshot.last30DaysTokens, 1_950)
        XCTAssertEqual(snapshot.todayCostUSD, 0.005625, accuracy: 0.000001)
    }

    func testUpdatesCachedCostWhenFileChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayDir = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("22", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = dayDir.appendingPathComponent("rollout.jsonl")
        let original = #"{"timestamp":"2026-04-22T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":100}}}}"#
        try original.write(to: file, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cacheStore = AgentBarCacheStore(fileURL: root.appendingPathComponent("cache.json"))
        let scanner = CodexCostScanner(sessionsRoot: root, calendar: calendar, cacheStore: cacheStore)
        let now = CodexCostScanner.parseTimestamp("2026-04-22T12:00:00.000Z")!

        XCTAssertEqual(scanner.scan(now: now).todayTokens, 1_100)

        let modified = #"{"timestamp":"2026-04-22T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":0,"output_tokens":200}}}}"#
        try modified.write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(scanner.scan(now: now).todayTokens, 2_200)
    }

    func testPricesGPT55TokenCountEvents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayDir = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("25", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = dayDir.appendingPathComponent("rollout.jsonl")
        let lines = [
            #"{"timestamp":"2026-04-25T10:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.5"}}"#,
            #"{"timestamp":"2026-04-25T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100,"total_tokens":1100}}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanner = CodexCostScanner(
            sessionsRoot: root,
            calendar: calendar,
            cacheStore: AgentBarCacheStore(fileURL: root.appendingPathComponent("cache.json")))
        let now = CodexCostScanner.parseTimestamp("2026-04-25T12:00:00.000Z")!

        let snapshot = scanner.scan(now: now)

        XCTAssertEqual(snapshot.todayTokens, 1_100)
        XCTAssertEqual(snapshot.last30DaysTokens, 1_100)
        XCTAssertEqual(snapshot.todayCostUSD, 0.0071, accuracy: 0.000001)
    }

    func testRepricesCachedGPT55ZeroCostFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayDir = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("25", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = dayDir.appendingPathComponent("rollout.jsonl")
        let lines = [
            #"{"timestamp":"2026-04-25T10:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.5"}}"#,
            #"{"timestamp":"2026-04-25T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100,"total_tokens":1100}}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        guard let metadata = CachedFileMetadata(fileURL: file) else {
            return XCTFail("Expected test file metadata")
        }
        let cacheStore = AgentBarCacheStore(fileURL: root.appendingPathComponent("cache.json"))
        cacheStore.update { cache in
            cache.costFiles[file.path] = CachedCostFile(
                metadata: metadata,
                days: [
                    "2026-04-25": [
                        "gpt-5.5": TokenTotals(totalTokens: 1_100, costUSD: 0),
                    ],
                ])
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanner = CodexCostScanner(sessionsRoot: root, calendar: calendar, cacheStore: cacheStore)
        let now = CodexCostScanner.parseTimestamp("2026-04-25T12:00:00.000Z")!

        let snapshot = scanner.scan(now: now)

        XCTAssertEqual(snapshot.todayTokens, 1_100)
        XCTAssertEqual(snapshot.todayCostUSD, 0.0071, accuracy: 0.000001)
        XCTAssertEqual(cacheStore.load().version, AgentBarCache.currentVersion)
    }

    func testDailyUsageSplitsLongLivedSessionByEventTimestamp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayDir = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("24", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = dayDir.appendingPathComponent("rollout-cross-day.jsonl")
        let lines = [
            #"{"timestamp":"2026-04-24T10:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-04-24T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":100}}}}"#,
            #"{"timestamp":"2026-04-25T02:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1300,"cached_input_tokens":100,"output_tokens":150}}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanner = CodexCostScanner(
            sessionsRoot: root,
            calendar: calendar,
            cacheStore: AgentBarCacheStore(fileURL: root.appendingPathComponent("cache.json")))
        let now = CodexCostScanner.parseTimestamp("2026-04-25T12:00:00.000Z")!

        let usage = scanner.dailyTokenUsage(days: 2, now: now)

        XCTAssertEqual(usage.days.map(\.dayKey), ["2026-04-24", "2026-04-25"])
        XCTAssertEqual(usage.days[0].tokens, 1_100)
        XCTAssertEqual(usage.days[1].tokens, 350)
        XCTAssertEqual(usage.totalTokens, 1_450)
    }

    func testDailyUsageFindsOlderSessionFileModifiedInsideWindow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oldDayDir = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("02", isDirectory: true)
            .appendingPathComponent("27", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDayDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = oldDayDir.appendingPathComponent("rollout-old-file-active-today.jsonl")
        let lines = [
            #"{"timestamp":"2026-04-25T02:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-04-25T02:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":20,"output_tokens":50}}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanner = CodexCostScanner(
            sessionsRoot: root,
            calendar: calendar,
            cacheStore: AgentBarCacheStore(fileURL: root.appendingPathComponent("cache.json")))
        let now = CodexCostScanner.parseTimestamp("2026-04-25T12:00:00.000Z")!

        let usage = scanner.dailyTokenUsage(days: 2, now: now)

        XCTAssertEqual(usage.days.map(\.tokens), [0, 350])
    }

    func testUsageRebucketsCachedEventsWhenLocalTimeZoneDiffersFromUTC() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayDir = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("26", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = dayDir.appendingPathComponent("rollout-local-midnight.jsonl")
        let lines = [
            #"{"timestamp":"2026-04-25T16:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-04-25T16:30:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":20,"output_tokens":50}}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        let cacheStore = AgentBarCacheStore(fileURL: root.appendingPathComponent("cache.json"))
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcScanner = CodexCostScanner(sessionsRoot: root, calendar: utcCalendar, cacheStore: cacheStore)
        let now = CodexCostScanner.parseTimestamp("2026-04-26T04:00:00.000Z")!

        let utcUsage = utcScanner.dailyTokenUsage(days: 2, now: now)
        XCTAssertEqual(utcUsage.days.map(\.dayKey), ["2026-04-25", "2026-04-26"])
        XCTAssertEqual(utcUsage.days.map(\.tokens), [350, 0])
        XCTAssertEqual(cacheStore.load().costFiles.values.first?.timeZoneIdentifier, "GMT")

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let localScanner = CodexCostScanner(sessionsRoot: root, calendar: localCalendar, cacheStore: cacheStore)

        let localDailyUsage = localScanner.dailyTokenUsage(days: 2, now: now)
        let localHourlyUsage = localScanner.hourlyTokenUsage(on: now)

        XCTAssertEqual(localDailyUsage.days.map(\.dayKey), ["2026-04-25", "2026-04-26"])
        XCTAssertEqual(localDailyUsage.days.map(\.tokens), [0, 350])
        XCTAssertEqual(localHourlyUsage.dayKey, "2026-04-26")
        XCTAssertEqual(localHourlyUsage.hours[0].totalTokens, 350)
        XCTAssertEqual(localHourlyUsage.hours[16].totalTokens, 0)
        XCTAssertEqual(cacheStore.load().costFiles.values.first?.timeZoneIdentifier, "Asia/Shanghai")
    }

    func testYearlyUsageReturnsCalendarYearDays() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayDir = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("25", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = dayDir.appendingPathComponent("rollout-year.jsonl")
        let line = #"{"timestamp":"2026-04-25T02:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":20,"output_tokens":50}}}}"#
        try line.write(to: file, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanner = CodexCostScanner(
            sessionsRoot: root,
            calendar: calendar,
            cacheStore: AgentBarCacheStore(fileURL: root.appendingPathComponent("cache.json")))
        let now = CodexCostScanner.parseTimestamp("2026-04-25T12:00:00.000Z")!

        let usage = scanner.yearlyTokenUsage(year: 2026, now: now)

        XCTAssertEqual(usage.days.first?.dayKey, "2026-01-01")
        XCTAssertEqual(usage.days.last?.dayKey, "2026-12-31")
        XCTAssertEqual(usage.days.count, 365)
        XCTAssertEqual(usage.days.first { $0.dayKey == "2026-04-25" }?.tokens, 350)
        XCTAssertEqual(scanner.usageYearRange(now: now), 2026...2026)
    }

    func testHourlyUsageSplitsTodayByHourAndModel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayDir = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("25", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = dayDir.appendingPathComponent("rollout-hourly.jsonl")
        let lines = [
            #"{"timestamp":"2026-04-25T08:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.5"}}"#,
            #"{"timestamp":"2026-04-25T08:10:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":100}}}}"#,
            #"{"timestamp":"2026-04-25T09:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-04-25T09:05:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":20,"output_tokens":50}}}}"#,
            #"{"timestamp":"2026-04-24T09:05:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":900,"cached_input_tokens":0,"output_tokens":100}}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanner = CodexCostScanner(
            sessionsRoot: root,
            calendar: calendar,
            cacheStore: AgentBarCacheStore(fileURL: root.appendingPathComponent("cache.json")))
        let now = CodexCostScanner.parseTimestamp("2026-04-25T12:00:00.000Z")!

        let usage = scanner.hourlyTokenUsage(on: now)

        XCTAssertEqual(usage.dayKey, "2026-04-25")
        XCTAssertEqual(usage.hours.count, 24)
        XCTAssertEqual(usage.hours[8].models.map(\.model), ["gpt-5.5"])
        XCTAssertEqual(usage.hours[8].totalTokens, 1_100)
        XCTAssertEqual(usage.hours[9].models.map(\.model), ["gpt-5.4"])
        XCTAssertEqual(usage.hours[9].totalTokens, 350)
        XCTAssertEqual(usage.totalTokens, 1_450)
        XCTAssertEqual(usage.maxHourlyTokens, 1_100)
    }
}
