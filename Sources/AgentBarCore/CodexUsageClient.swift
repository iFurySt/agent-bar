import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CodexRateLimitWindow: Codable, Equatable, Sendable {
    public let remainingPercent: Int?
    public let resetAt: Date?
    public let durationMinutes: Int?

    public init(remainingPercent: Int?, resetAt: Date? = nil, durationMinutes: Int? = nil) {
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
        self.durationMinutes = durationMinutes
    }

    public func displayLabel(fallback: String) -> String {
        guard let durationMinutes else { return fallback }
        switch durationMinutes {
        case 270...330: return "5h"
        case 1_380...1_500: return "Daily"
        case 9_720...10_440: return "7d"
        case 40_320...44_640: return "Monthly"
        case 518_400...527_040: return "Annual"
        default: return fallback
        }
    }
}

public struct CodexRateLimitSnapshot: Codable, Equatable, Sendable {
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?

    public init(primary: CodexRateLimitWindow?, secondary: CodexRateLimitWindow?) {
        self.primary = primary
        self.secondary = secondary
    }

    public init(
        fiveHourRemainingPercent: Int?,
        weeklyRemainingPercent: Int?,
        fiveHourResetAt: Date? = nil,
        weeklyResetAt: Date? = nil)
    {
        self.primary = CodexRateLimitWindow(
            remainingPercent: fiveHourRemainingPercent,
            resetAt: fiveHourResetAt,
            durationMinutes: 300)
        self.secondary = CodexRateLimitWindow(
            remainingPercent: weeklyRemainingPercent,
            resetAt: weeklyResetAt,
            durationMinutes: 10_080)
    }

    public var primaryLabel: String { primary?.displayLabel(fallback: "Usage") ?? "Usage" }
    public var secondaryLabel: String { secondary?.displayLabel(fallback: "Secondary") ?? "Secondary" }
    public var fiveHourRemainingPercent: Int? { primary?.remainingPercent }
    public var weeklyRemainingPercent: Int? { secondary?.remainingPercent }
    public var fiveHourResetAt: Date? { primary?.resetAt }
    public var weeklyResetAt: Date? { secondary?.resetAt }

    public var availableWindows: [CodexRateLimitWindow] {
        [primary, secondary]
            .compactMap { $0 }
            .filter { $0.remainingPercent != nil }
            .enumerated()
            .sorted { lhs, rhs in
                let leftDuration = lhs.element.durationMinutes ?? .max
                let rightDuration = rhs.element.durationMinutes ?? .max
                return leftDuration == rightDuration ? lhs.offset < rhs.offset : leftDuration < rightDuration
            }
            .map(\.element)
    }

    var hasAnyPercent: Bool {
        primary?.remainingPercent != nil || secondary?.remainingPercent != nil
    }

    func fillingMissing(with fallback: CodexRateLimitSnapshot) -> CodexRateLimitSnapshot {
        // A successful response containing only one window can be intentional
        // (for example a monthly-only rollout). Do not splice stale 5h/weekly
        // session data into that authoritative server shape.
        hasAnyPercent ? self : fallback
    }

    private enum CodingKeys: String, CodingKey {
        case primary, secondary
        case fiveHourRemainingPercent, weeklyRemainingPercent, fiveHourResetAt, weeklyResetAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.primary) || values.contains(.secondary) {
            primary = try values.decodeIfPresent(CodexRateLimitWindow.self, forKey: .primary)
            secondary = try values.decodeIfPresent(CodexRateLimitWindow.self, forKey: .secondary)
            return
        }
        let fiveHourPercent = try values.decodeIfPresent(Int.self, forKey: .fiveHourRemainingPercent)
        let weeklyPercent = try values.decodeIfPresent(Int.self, forKey: .weeklyRemainingPercent)
        let fiveHourReset = try values.decodeIfPresent(Date.self, forKey: .fiveHourResetAt)
        let weeklyReset = try values.decodeIfPresent(Date.self, forKey: .weeklyResetAt)
        primary = CodexRateLimitWindow(remainingPercent: fiveHourPercent, resetAt: fiveHourReset, durationMinutes: 300)
        secondary = CodexRateLimitWindow(remainingPercent: weeklyPercent, resetAt: weeklyReset, durationMinutes: 10_080)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(primary, forKey: .primary)
        try values.encodeIfPresent(secondary, forKey: .secondary)
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
            primary: Self.snapshot(decoded.rateLimit?.primaryWindow),
            secondary: Self.snapshot(decoded.rateLimit?.secondaryWindow))
        return (rateLimits, Self.planLabel(decoded.planType))
    }

    static func snapshot(_ window: CodexUsageResponse.Window?) -> CodexRateLimitWindow? {
        guard let window else { return nil }
        return CodexRateLimitWindow(
            remainingPercent: remainingPercent(window),
            resetAt: resetDate(window),
            durationMinutes: window.limitWindowSeconds.map { $0 / 60 })
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
