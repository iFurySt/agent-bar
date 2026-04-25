import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CodexAuthCredentials: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let accountId: String?
    let lastRefresh: Date?

    var needsRefresh: Bool {
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > 8 * 24 * 60 * 60
    }
}

public enum CodexHome {
    public static func url(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let raw = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }
}

enum CodexAuthStore {
    static func authFileURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        CodexHome.url(env: env).appendingPathComponent("auth.json")
    }

    static func load(env: [String: String] = ProcessInfo.processInfo.environment) throws -> CodexAuthCredentials {
        let url = authFileURL(env: env)
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> CodexAuthCredentials {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentBarError("Invalid Codex auth.json")
        }

        if let apiKey = json["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return CodexAuthCredentials(
                accessToken: apiKey,
                refreshToken: "",
                idToken: nil,
                accountId: nil,
                lastRefresh: nil)
        }

        guard let tokens = json["tokens"] as? [String: Any] else {
            throw AgentBarError("Codex auth.json has no tokens")
        }

        guard let accessToken = stringValue(in: tokens, snake: "access_token", camel: "accessToken"),
              !accessToken.isEmpty
        else {
            throw AgentBarError("Codex access token is missing")
        }

        return CodexAuthCredentials(
            accessToken: accessToken,
            refreshToken: stringValue(in: tokens, snake: "refresh_token", camel: "refreshToken") ?? "",
            idToken: stringValue(in: tokens, snake: "id_token", camel: "idToken"),
            accountId: stringValue(in: tokens, snake: "account_id", camel: "accountId"),
            lastRefresh: parseDate(json["last_refresh"]))
    }

    static func save(
        _ credentials: CodexAuthCredentials,
        env: [String: String] = ProcessInfo.processInfo.environment) throws
    {
        let url = authFileURL(env: env)
        var json: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any]
        {
            json = existing
        }

        var tokens: [String: Any] = [
            "access_token": credentials.accessToken,
            "refresh_token": credentials.refreshToken,
        ]
        if let idToken = credentials.idToken {
            tokens["id_token"] = idToken
        }
        if let accountId = credentials.accountId {
            tokens["account_id"] = accountId
        }

        json["tokens"] = tokens
        json["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func stringValue(in dictionary: [String: Any], snake: String, camel: String) -> String? {
        if let value = dictionary[snake] as? String, !value.isEmpty { return value }
        if let value = dictionary[camel] as? String, !value.isEmpty { return value }
        return nil
    }

    private static func parseDate(_ raw: Any?) -> Date? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum CodexTokenRefresher {
    private static let refreshEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    static func refresh(_ credentials: CodexAuthCredentials) async throws -> CodexAuthCredentials {
        guard !credentials.refreshToken.isEmpty else { return credentials }

        var request = URLRequest(url: refreshEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "scope": "openid profile email",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentBarError("No HTTP response while refreshing Codex token")
        }
        guard http.statusCode == 200 else {
            throw AgentBarError("Codex token refresh failed with HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentBarError("Invalid Codex token refresh response")
        }

        return CodexAuthCredentials(
            accessToken: json["access_token"] as? String ?? credentials.accessToken,
            refreshToken: json["refresh_token"] as? String ?? credentials.refreshToken,
            idToken: json["id_token"] as? String ?? credentials.idToken,
            accountId: json["account_id"] as? String ?? credentials.accountId,
            lastRefresh: Date())
    }
}
