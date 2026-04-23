import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CodexRateLimitSnapshot: Codable, Equatable, Sendable {
    public let fiveHourRemainingPercent: Int?
    public let weeklyRemainingPercent: Int?

    public init(fiveHourRemainingPercent: Int?, weeklyRemainingPercent: Int?) {
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
    }

    var hasMissingPercent: Bool {
        fiveHourRemainingPercent == nil || weeklyRemainingPercent == nil
    }

    func fillingMissing(with fallback: CodexRateLimitSnapshot) -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            fiveHourRemainingPercent: fiveHourRemainingPercent ?? fallback.fiveHourRemainingPercent,
            weeklyRemainingPercent: weeklyRemainingPercent ?? fallback.weeklyRemainingPercent)
    }
}

struct CodexUsageResponse: Decodable {
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }
}

public final class CodexUsageClient: @unchecked Sendable {
    public init() {}

    public func fetchRateLimits() async throws -> CodexRateLimitSnapshot {
        var credentials = try CodexAuthStore.load()
        if credentials.needsRefresh {
            credentials = try await CodexTokenRefresher.refresh(credentials)
            try CodexAuthStore.save(credentials)
        }

        do {
            return try await fetchRateLimits(credentials: credentials)
        } catch {
            if !credentials.refreshToken.isEmpty {
                let refreshed = try await CodexTokenRefresher.refresh(credentials)
                try CodexAuthStore.save(refreshed)
                return try await fetchRateLimits(credentials: refreshed)
            }
            throw error
        }
    }

    private func fetchRateLimits(credentials: CodexAuthCredentials) async throws -> CodexRateLimitSnapshot {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("AgentBar", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = credentials.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentBarError("No HTTP response from Codex usage API")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AgentBarError("Codex usage API failed with HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        return CodexRateLimitSnapshot(
            fiveHourRemainingPercent: Self.remainingPercent(decoded.rateLimit?.primaryWindow),
            weeklyRemainingPercent: Self.remainingPercent(decoded.rateLimit?.secondaryWindow))
    }

    static func remainingPercent(_ window: CodexUsageResponse.Window?) -> Int? {
        guard let window else { return nil }
        return min(100, max(0, Int((100 - window.usedPercent).rounded())))
    }
}
