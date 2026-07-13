import XCTest
@testable import AgentBarCore

final class DisplayFormattingTests: XCTestCase {
    func testFormatsSnapshotLine() {
        let snapshot = AgentBarSnapshot(
            rateLimits: CodexRateLimitSnapshot(fiveHourRemainingPercent: 4, weeklyRemainingPercent: 46),
            costs: CodexCostSnapshot(
                todayCostUSD: 114.2,
                todayTokens: 293_000_000,
                last30DaysCostUSD: 1_443.43,
                last30DaysTokens: 3_300_000_000))

        XCTAssertEqual(
            AgentBarDisplayFormatting.line(snapshot: snapshot),
            "5h 4%  7d 46%  Today: $114.20 · 293M/~30 Days: $1,443.43 · 3.3B Tokens")
    }

    func testFormatsMonthlyPrimaryWithoutGuessingSecondaryDuration() {
        let snapshot = AgentBarSnapshot(
            rateLimits: CodexRateLimitSnapshot(
                primary: CodexRateLimitWindow(remainingPercent: 55, durationMinutes: 43_200),
                secondary: CodexRateLimitWindow(remainingPercent: nil)),
            costs: CodexCostSnapshot(
                todayCostUSD: 0,
                todayTokens: 0,
                last30DaysCostUSD: 0,
                last30DaysTokens: 0))

        XCTAssertEqual(
            AgentBarDisplayFormatting.line(snapshot: snapshot),
            "Monthly 55%  Today: $0.00 · 0/~30 Days: $0.00 · 0 Tokens")
    }

    func testFormatsOnlyAvailableSecondaryWindow() {
        let snapshot = AgentBarSnapshot(
            rateLimits: CodexRateLimitSnapshot(
                primary: nil,
                secondary: CodexRateLimitWindow(remainingPercent: 99, durationMinutes: 10_080)),
            costs: CodexCostSnapshot(
                todayCostUSD: 0,
                todayTokens: 0,
                last30DaysCostUSD: 0,
                last30DaysTokens: 0))

        XCTAssertEqual(
            AgentBarDisplayFormatting.line(snapshot: snapshot),
            "7d 99%  Today: $0.00 · 0/~30 Days: $0.00 · 0 Tokens")
    }

    func testOrdersAvailableWindowsFromShortestToLongest() {
        let snapshot = AgentBarSnapshot(
            rateLimits: CodexRateLimitSnapshot(
                primary: CodexRateLimitWindow(remainingPercent: 99, durationMinutes: 10_080),
                secondary: CodexRateLimitWindow(remainingPercent: 97, durationMinutes: 300)),
            costs: CodexCostSnapshot(
                todayCostUSD: 0,
                todayTokens: 0,
                last30DaysCostUSD: 0,
                last30DaysTokens: 0))

        XCTAssertEqual(
            AgentBarDisplayFormatting.line(snapshot: snapshot),
            "5h 97%  7d 99%  Today: $0.00 · 0/~30 Days: $0.00 · 0 Tokens")
    }

    func testTokenFormatting() {
        XCTAssertEqual(AgentBarDisplayFormatting.tokens(950), "950")
        XCTAssertEqual(AgentBarDisplayFormatting.tokens(12_400), "12.4K")
        XCTAssertEqual(AgentBarDisplayFormatting.tokens(293_000_000), "293M")
        XCTAssertEqual(AgentBarDisplayFormatting.tokens(3_300_000_000), "3.3B")
        XCTAssertEqual(AgentBarDisplayFormatting.tokens(9_161_800_000), "9.2B")
    }
}
