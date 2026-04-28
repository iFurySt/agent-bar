import XCTest
@testable import AgentBarCore

final class CodexActivityScannerTests: XCTestCase {
    func testHourlyActivityUsageSplitsBlocksAcrossHours() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayDir = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("25", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = dayDir.appendingPathComponent("rollout-activity.jsonl")
        let lines = [
            #"{"timestamp":"2026-04-25T08:50:00.000Z","type":"response_item","payload":{"item":{"role":"user","content":[{"type":"input_text","text":"build"}]}}}"#,
            #"{"timestamp":"2026-04-25T08:55:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":50}}}}"#,
            #"{"timestamp":"2026-04-25T09:10:00.000Z","type":"event_msg","payload":{"type":"exec_command_end","duration":420,"exit_code":0}}"#,
            #"{"timestamp":"2026-04-25T12:00:00.000Z","type":"response_item","payload":{"item":{"role":"assistant","content":[{"type":"output_text","text":"done"}]}}}"#,
            #"{"timestamp":"2026-04-24T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":50}}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanner = CodexActivityScanner(sessionsRoot: root, calendar: calendar)
        let day = CodexCostScanner.parseTimestamp("2026-04-25T12:00:00.000Z")!

        let usage = scanner.hourlyActivityUsage(on: day)

        XCTAssertEqual(usage.dayKey, "2026-04-25")
        XCTAssertEqual(usage.hours.count, 24)
        XCTAssertEqual(usage.hours[8].minutes, 10, accuracy: 0.001)
        XCTAssertEqual(usage.hours[9].minutes, 10, accuracy: 0.001)
        XCTAssertEqual(usage.totalMinutes, 20, accuracy: 0.001)
        XCTAssertEqual(usage.maxHourlyMinutes, 10, accuracy: 0.001)
    }
}
