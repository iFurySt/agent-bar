import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ClaudeAuthCredentials: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
    let subscriptionType: String?

    var needsRefresh: Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(5 * 60) >= expiresAt
    }
}

public enum ClaudeHome {
    public static func url(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }
}

enum ClaudeAuthStore {
    // AgentBar polls Claude Code's quota on a timer; without this cache every
    // tick would re-read the credentials file even though nothing changed. A
    // cheap file-mtime/size check lets a fresh `claude` login invalidate the
    // cache immediately.
    //
    // Only `~/.claude/.credentials.json` is read. Claude Code can also store
    // credentials in the macOS Keychain, but non-interactive Keychain reads
    // aren't reliably prompt-free across systems, and AgentBar's Claude quota
    // card has no user-initiated action to gate an interactive fallback
    // behind — so background polling never touches the Keychain at all.
    private static let memoryCacheValidityDuration: TimeInterval = 30 * 60
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cachedCredentials: ClaudeAuthCredentials?
    private nonisolated(unsafe) static var cachedAt: Date?
    private nonisolated(unsafe) static var cachedFileFingerprint: FileFingerprint?

    struct FileFingerprint: Equatable {
        let modifiedAt: Date?
        let size: Int
    }

    static func credentialsFileURL() -> URL {
        ClaudeHome.url().appendingPathComponent(".credentials.json")
    }

    static func hasCredentials() -> Bool {
        (try? load()) != nil
    }

    static func load() throws -> ClaudeAuthCredentials {
        if let cached = readValidCache() {
            return cached
        }

        guard let data = try? Data(contentsOf: credentialsFileURL()) else {
            throw AgentBarError("No Claude Code credentials found")
        }
        let credentials = try parse(data: data)
        writeCache(credentials, fileFingerprint: currentFileFingerprint())
        return credentials
    }

    static func save(_ credentials: ClaudeAuthCredentials) {
        let payload = encode(credentials)
        try? payload.write(to: credentialsFileURL(), options: .atomic)
        writeCache(credentials, fileFingerprint: currentFileFingerprint())
    }

    private static func readValidCache() -> ClaudeAuthCredentials? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let cachedCredentials, let cachedAt,
              Date().timeIntervalSince(cachedAt) < memoryCacheValidityDuration,
              currentFileFingerprint() == cachedFileFingerprint
        else { return nil }
        return cachedCredentials
    }

    private static func writeCache(_ credentials: ClaudeAuthCredentials, fileFingerprint: FileFingerprint?) {
        cacheLock.lock()
        cachedCredentials = credentials
        cachedAt = Date()
        cachedFileFingerprint = fileFingerprint
        cacheLock.unlock()
    }

    private static func currentFileFingerprint() -> FileFingerprint? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: credentialsFileURL().path)
        else { return nil }
        return FileFingerprint(
            modifiedAt: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.intValue ?? 0)
    }

    static func parse(data: Data) throws -> ClaudeAuthCredentials {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty
        else {
            throw AgentBarError("Invalid Claude Code credentials")
        }

        return ClaudeAuthCredentials(
            accessToken: accessToken,
            refreshToken: oauth["refreshToken"] as? String ?? "",
            expiresAt: (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) },
            subscriptionType: oauth["subscriptionType"] as? String)
    }

    private static func encode(_ credentials: ClaudeAuthCredentials) -> Data {
        var oauth: [String: Any] = [
            "accessToken": credentials.accessToken,
            "refreshToken": credentials.refreshToken,
        ]
        if let expiresAt = credentials.expiresAt {
            oauth["expiresAt"] = Int64(expiresAt.timeIntervalSince1970 * 1000)
        }
        if let subscriptionType = credentials.subscriptionType {
            oauth["subscriptionType"] = subscriptionType
        }
        let json: [String: Any] = ["claudeAiOauth": oauth]
        return (try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}

enum ClaudeTokenRefresher {
    private static let refreshEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    static func refresh(_ credentials: ClaudeAuthCredentials) async throws -> ClaudeAuthCredentials {
        guard !credentials.refreshToken.isEmpty else { return credentials }

        var request = URLRequest(url: refreshEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "client_id": clientID,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AgentBarError("Claude Code token refresh failed")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String
        else {
            throw AgentBarError("Invalid Claude Code token refresh response")
        }

        let expiresAt: Date? = (json["expires_in"] as? NSNumber)
            .map { Date().addingTimeInterval($0.doubleValue) } ?? credentials.expiresAt

        return ClaudeAuthCredentials(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String ?? credentials.refreshToken,
            expiresAt: expiresAt,
            subscriptionType: credentials.subscriptionType)
    }
}
