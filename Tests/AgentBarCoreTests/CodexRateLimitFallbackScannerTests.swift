import XCTest
@testable import AgentBarCore

final class CodexRateLimitFallbackScannerTests: XCTestCase {
    func testPrefersBaseCodexLimitOverNewerModelSpecificLimit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("session.jsonl")
        let lines = [
            #"{"timestamp":"2026-04-23T06:52:44.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":37.0},"secondary":{"used_percent":43.0}}}}"#,
            #"{"timestamp":"2026-04-23T06:52:45.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":0.0},"secondary":{"used_percent":0.0}}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        let snapshot = CodexRateLimitFallbackScanner(sessionsRoot: root).latestRateLimits()

        XCTAssertEqual(snapshot.fiveHourRemainingPercent, 63)
        XCTAssertEqual(snapshot.weeklyRemainingPercent, 57)
    }

    func testFillsMissingFetchedRateLimitsFromFallback() {
        let fetched = CodexRateLimitSnapshot(fiveHourRemainingPercent: nil, weeklyRemainingPercent: 57)
        let fallback = CodexRateLimitSnapshot(fiveHourRemainingPercent: 63, weeklyRemainingPercent: 12)

        XCTAssertEqual(
            fetched.fillingMissing(with: fallback),
            CodexRateLimitSnapshot(fiveHourRemainingPercent: 63, weeklyRemainingPercent: 57))
    }
}
