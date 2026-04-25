import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CodexRateLimitSnapshot: Codable, Equatable, Sendable {
    public let fiveHourRemainingPercent: Int?
    public let weeklyRemainingPercent: Int?
    public let fiveHourResetAt: Date?
    public let weeklyResetAt: Date?

    public init(
        fiveHourRemainingPercent: Int?,
        weeklyRemainingPercent: Int?,
        fiveHourResetAt: Date? = nil,
        weeklyResetAt: Date? = nil)
    {
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.fiveHourResetAt = fiveHourResetAt
        self.weeklyResetAt = weeklyResetAt
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
    let planType: String?
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
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
        let resetAt: Int?
        let limitWindowSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }
}

public final class CodexUsageClient: @unchecked Sendable {
    public init() {}

    public func fetchRateLimits() async throws -> CodexRateLimitSnapshot {
        var credentials = try CodexAuthStore.load()
        CodexAccountStore.upsert(credentials)
        if credentials.needsRefresh {
            credentials = try await CodexTokenRefresher.refresh(credentials)
            try CodexAuthStore.save(credentials)
            CodexAccountStore.upsert(credentials)
        }

        do {
            return try await fetchRateLimits(credentials: credentials)
        } catch {
            if !credentials.refreshToken.isEmpty {
                let refreshed = try await CodexTokenRefresher.refresh(credentials)
                try CodexAuthStore.save(refreshed)
                CodexAccountStore.upsert(refreshed)
                return try await fetchRateLimits(credentials: refreshed)
            }
            throw error
        }
    }

    public func fetchAccountRateLimits() async -> [CodexAccountUsageSnapshot] {
        let current = try? CodexAuthStore.load()
        if let current {
            CodexAccountStore.upsert(current)
        }

        let currentID = current?.stableAccountID
        var snapshots: [CodexAccountUsageSnapshot] = []
        for stored in CodexAccountStore.load() {
            var credentials = stored.credentials
            var updatedAt = stored.updatedAt
            if credentials.needsRefresh, !credentials.refreshToken.isEmpty,
               let refreshed = try? await CodexTokenRefresher.refresh(credentials)
            {
                credentials = refreshed
                let updated = CodexStoredAccount(
                    id: refreshed.stableAccountID,
                    label: refreshed.displayLabel,
                    credentials: refreshed,
                    createdAt: stored.createdAt,
                    updatedAt: Date())
                updatedAt = updated.updatedAt
                CodexAccountStore.update(updated)
            }

            let usage = try? await fetchUsage(credentials: credentials)
            let rateLimits = usage?.rateLimits
                ?? CodexRateLimitSnapshot(fiveHourRemainingPercent: nil, weeklyRemainingPercent: nil)
            snapshots.append(CodexAccountUsageSnapshot(
                id: credentials.stableAccountID,
                label: credentials.displayLabel,
                rateLimits: rateLimits,
                isCurrent: credentials.stableAccountID == currentID,
                updatedAt: updatedAt,
                plan: usage?.plan))
        }
        return snapshots.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }

    private func fetchRateLimits(credentials: CodexAuthCredentials) async throws -> CodexRateLimitSnapshot {
        try await fetchUsage(credentials: credentials).rateLimits
    }

    private func fetchUsage(credentials: CodexAuthCredentials) async throws -> (rateLimits: CodexRateLimitSnapshot, plan: String?) {
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
        let rateLimits = CodexRateLimitSnapshot(
            fiveHourRemainingPercent: Self.remainingPercent(decoded.rateLimit?.primaryWindow),
            weeklyRemainingPercent: Self.remainingPercent(decoded.rateLimit?.secondaryWindow),
            fiveHourResetAt: Self.resetDate(decoded.rateLimit?.primaryWindow),
            weeklyResetAt: Self.resetDate(decoded.rateLimit?.secondaryWindow))
        return (rateLimits, Self.planLabel(decoded.planType))
    }

    static func remainingPercent(_ window: CodexUsageResponse.Window?) -> Int? {
        guard let window else { return nil }
        return min(100, max(0, Int((100 - window.usedPercent).rounded())))
    }

    static func resetDate(_ window: CodexUsageResponse.Window?) -> Date? {
        guard let resetAt = window?.resetAt, resetAt > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(resetAt))
    }

    static func planLabel(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        switch raw.lowercased() {
        case "plus":
            return "PLUS"
        case "pro":
            return "PRO"
        case "team":
            return "TEAM"
        case "business":
            return "BUSINESS"
        case "enterprise":
            return "ENTERPRISE"
        case "free":
            return "FREE"
        case "go":
            return "GO"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }
}
