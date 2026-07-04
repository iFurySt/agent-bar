import XCTest
@testable import AgentBarCore

final class ClaudeAuthTests: XCTestCase {
    func testParsesCredentialsFileFormat() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "access-123",
            "refreshToken": "refresh-456",
            "expiresAt": 1783179968485,
            "scopes": ["user:inference"],
            "subscriptionType": "pro",
            "rateLimitTier": "default_claude_ai"
          }
        }
        """
        let credentials = try ClaudeAuthStore.parse(data: Data(json.utf8), source: .file)

        XCTAssertEqual(credentials.accessToken, "access-123")
        XCTAssertEqual(credentials.refreshToken, "refresh-456")
        XCTAssertEqual(credentials.subscriptionType, "pro")
        let expiresAt = try XCTUnwrap(credentials.expiresAt)
        XCTAssertEqual(expiresAt.timeIntervalSince1970, 1_783_179_968.485, accuracy: 0.001)
    }

    func testThrowsOnMissingAccessToken() {
        let json = #"{"claudeAiOauth":{"refreshToken":"refresh-456"}}"#
        XCTAssertThrowsError(try ClaudeAuthStore.parse(data: Data(json.utf8), source: .file))
    }

    func testThrowsOnMissingOauthPayload() {
        let json = #"{"somethingElse": true}"#
        XCTAssertThrowsError(try ClaudeAuthStore.parse(data: Data(json.utf8), source: .file))
    }

    func testNeedsRefreshWhenExpiringSoon() {
        let expiringSoon = ClaudeAuthCredentials(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: Date().addingTimeInterval(60),
            subscriptionType: "pro",
            source: .file)
        XCTAssertTrue(expiringSoon.needsRefresh)

        let freshForAWhile = ClaudeAuthCredentials(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600),
            subscriptionType: "pro",
            source: .file)
        XCTAssertFalse(freshForAWhile.needsRefresh)

        let noExpiry = ClaudeAuthCredentials(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: nil,
            subscriptionType: nil,
            source: .file)
        XCTAssertFalse(noExpiry.needsRefresh)
    }
}

final class ClaudeUsageClientTests: XCTestCase {
    func testRemainingPercentClampsAndRounds() {
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(nil), nil)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(.init(utilization: 0, resetsAt: nil)), 100)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(.init(utilization: 96, resetsAt: nil)), 4)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(.init(utilization: 100, resetsAt: nil)), 0)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(.init(utilization: 120, resetsAt: nil)), 0)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(.init(utilization: -10, resetsAt: nil)), 100)
    }

    func testDecodesUsageResponseSnakeCaseWindows() throws {
        let json = #"""
        {"five_hour":{"utilization":25.4,"resets_at":"2026-07-04T18:09:59.908091+00:00"},
         "seven_day":{"utilization":60,"resets_at":"2026-07-06T23:59:59.908112+00:00"}}
        """#
        let decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(json.utf8))

        XCTAssertEqual(ClaudeUsageClient.remainingPercent(decoded.fiveHour), 75)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(decoded.sevenDay), 40)

        let fiveHourReset = try XCTUnwrap(ClaudeUsageClient.resetDate(decoded.fiveHour))
        XCTAssertEqual(fiveHourReset.timeIntervalSince1970, 1_783_188_599.908, accuracy: 0.01)
    }

    func testPlanLabelMapsKnownSubscriptionTiers() {
        XCTAssertEqual(ClaudeUsageClient.planLabel(nil), nil)
        XCTAssertEqual(ClaudeUsageClient.planLabel(""), nil)
        XCTAssertEqual(ClaudeUsageClient.planLabel("pro"), "PRO")
        XCTAssertEqual(ClaudeUsageClient.planLabel("max"), "MAX")
        XCTAssertEqual(ClaudeUsageClient.planLabel("team"), "TEAM")
        XCTAssertEqual(ClaudeUsageClient.planLabel("some_other_tier"), "SOME OTHER TIER")
    }
}
