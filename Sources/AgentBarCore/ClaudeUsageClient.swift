import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ClaudeRateLimitSnapshot: Codable, Equatable, Sendable {
    public let fiveHourRemainingPercent: Int?
    public let weeklyRemainingPercent: Int?

    public init(fiveHourRemainingPercent: Int?, weeklyRemainingPercent: Int?) {
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
    }
}

struct ClaudeUsageResponse: Decodable {
    let fiveHour: Window?
    let sevenDay: Window?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    struct Window: Decodable {
        let utilization: Double
    }
}

public final class ClaudeUsageClient: @unchecked Sendable {
    public init() {}

    public static func hasCredentials() -> Bool {
        ClaudeAuthStore.hasCredentials()
    }

    public func fetchRateLimits() async throws -> ClaudeRateLimitSnapshot {
        var credentials = try ClaudeAuthStore.load()
        if credentials.needsRefresh, !credentials.refreshToken.isEmpty {
            credentials = try await ClaudeTokenRefresher.refresh(credentials)
            ClaudeAuthStore.save(credentials)
        }

        do {
            return try await fetchUsage(credentials: credentials)
        } catch {
            guard !credentials.refreshToken.isEmpty else { throw error }
            let refreshed = try await ClaudeTokenRefresher.refresh(credentials)
            ClaudeAuthStore.save(refreshed)
            return try await fetchUsage(credentials: refreshed)
        }
    }

    private func fetchUsage(credentials: ClaudeAuthCredentials) async throws -> ClaudeRateLimitSnapshot {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentBarError("No HTTP response from Claude usage API")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AgentBarError("Claude usage API failed with HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        return ClaudeRateLimitSnapshot(
            fiveHourRemainingPercent: Self.remainingPercent(decoded.fiveHour),
            weeklyRemainingPercent: Self.remainingPercent(decoded.sevenDay))
    }

    static func remainingPercent(_ window: ClaudeUsageResponse.Window?) -> Int? {
        guard let window else { return nil }
        return min(100, max(0, Int((100 - window.utilization).rounded())))
    }
}
