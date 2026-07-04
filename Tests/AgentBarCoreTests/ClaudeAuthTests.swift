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
            source: .file)
        XCTAssertTrue(expiringSoon.needsRefresh)

        let freshForAWhile = ClaudeAuthCredentials(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600),
            source: .file)
        XCTAssertFalse(freshForAWhile.needsRefresh)

        let noExpiry = ClaudeAuthCredentials(accessToken: "a", refreshToken: "r", expiresAt: nil, source: .file)
        XCTAssertFalse(noExpiry.needsRefresh)
    }
}

final class ClaudeUsageClientTests: XCTestCase {
    func testRemainingPercentClampsAndRounds() {
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(nil), nil)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(.init(utilization: 0)), 100)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(.init(utilization: 96)), 4)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(.init(utilization: 100)), 0)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(.init(utilization: 120)), 0)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(.init(utilization: -10)), 100)
    }

    func testDecodesUsageResponseSnakeCaseWindows() throws {
        let json = #"{"five_hour":{"utilization":25.4},"seven_day":{"utilization":60}}"#
        let decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(json.utf8))

        XCTAssertEqual(ClaudeUsageClient.remainingPercent(decoded.fiveHour), 75)
        XCTAssertEqual(ClaudeUsageClient.remainingPercent(decoded.sevenDay), 40)
    }
}
