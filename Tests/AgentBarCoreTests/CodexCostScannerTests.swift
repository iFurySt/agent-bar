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
        let scanner = CodexCostScanner(sessionsRoot: root, calendar: calendar)
        let now = CodexCostScanner.parseTimestamp("2026-04-22T12:00:00.000Z")!

        let snapshot = scanner.scan(now: now)

        XCTAssertEqual(snapshot.todayTokens, 1_950)
        XCTAssertEqual(snapshot.last30DaysTokens, 1_950)
        XCTAssertEqual(snapshot.todayCostUSD, 0.005625, accuracy: 0.000001)
    }
}
