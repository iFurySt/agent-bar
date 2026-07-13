import XCTest
@testable import AgentBarCore

final class CodexUsageClientTests: XCTestCase {
    func testDecodesGeneralizedUsageWindows() throws {
        let data = Data(#"""
        {
          "plan_type":"plus",
          "rate_limit":{
            "primary_window":{"used_percent":45.2,"reset_at":1783180800,"limit_window_seconds":2592000},
            "secondary_window":null
          }
        }
        """#.utf8)

        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        let primary = try XCTUnwrap(CodexUsageClient.snapshot(response.rateLimit?.primaryWindow))

        XCTAssertEqual(primary.remainingPercent, 55)
        XCTAssertEqual(primary.durationMinutes, 43_200)
        XCTAssertEqual(primary.displayLabel(fallback: "Usage"), "Monthly")
        XCTAssertNil(response.rateLimit?.secondaryWindow)
    }

    func testUnknownWindowUsesGenericLabel() {
        let window = CodexRateLimitWindow(remainingPercent: 80, durationMinutes: 720)
        XCTAssertEqual(window.displayLabel(fallback: "Usage"), "Usage")
    }

    func testDecodesLegacyRateLimitSnapshotCache() throws {
        let data = Data(#"""
        {
          "fiveHourRemainingPercent":63,
          "weeklyRemainingPercent":57,
          "fiveHourResetAt":0,
          "weeklyResetAt":60
        }
        """#.utf8)

        let snapshot = try JSONDecoder().decode(CodexRateLimitSnapshot.self, from: data)

        XCTAssertEqual(snapshot.primary?.remainingPercent, 63)
        XCTAssertEqual(snapshot.primary?.durationMinutes, 300)
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 57)
        XCTAssertEqual(snapshot.secondary?.durationMinutes, 10_080)
    }
}
