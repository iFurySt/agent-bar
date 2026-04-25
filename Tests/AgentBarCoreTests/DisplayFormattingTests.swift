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

    func testTokenFormatting() {
        XCTAssertEqual(AgentBarDisplayFormatting.tokens(950), "950")
        XCTAssertEqual(AgentBarDisplayFormatting.tokens(12_400), "12.4K")
        XCTAssertEqual(AgentBarDisplayFormatting.tokens(293_000_000), "293M")
        XCTAssertEqual(AgentBarDisplayFormatting.tokens(3_300_000_000), "3.3B")
    }
}
