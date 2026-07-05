import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#endif
#if canImport(Security)
import Security
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

struct ClaudeAuthCredentials: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
    let subscriptionType: String?
    let source: ClaudeCredentialSource

    var needsRefresh: Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(5 * 60) >= expiresAt
    }
}

enum ClaudeCredentialSource: Sendable {
    case file
    case keychain
}

public enum ClaudeHome {
    public static func url(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }
}

enum ClaudeAuthStore {
    private static let keychainService = "Claude Code-credentials"
    private static let keychainUIFailPolicy = resolveKeychainUIFailPolicy()

    static func credentialsFileURL() -> URL {
        ClaudeHome.url().appendingPathComponent(".credentials.json")
    }

    static func hasCredentials() -> Bool {
        (try? load()) != nil
    }

    static func load() throws -> ClaudeAuthCredentials {
        if let data = try? Data(contentsOf: credentialsFileURL()) {
            return try parse(data: data, source: .file)
        }
        guard let data = readKeychain() else {
            throw AgentBarError("No Claude Code credentials found")
        }
        return try parse(data: data, source: .keychain)
    }

    static func save(_ credentials: ClaudeAuthCredentials) {
        let payload = encode(credentials)
        switch credentials.source {
        case .file:
            try? payload.write(to: credentialsFileURL(), options: .atomic)
        case .keychain:
            writeKeychain(payload)
        }
    }

    static func parse(data: Data, source: ClaudeCredentialSource) throws -> ClaudeAuthCredentials {
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
            subscriptionType: oauth["subscriptionType"] as? String,
            source: source)
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

    private static func readKeychain() -> Data? {
        #if canImport(Security)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        query.merge(nonInteractiveKeychainOptions()) { _, new in new }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
        #else
        return nil
        #endif
    }

    private static func writeKeychain(_ data: Data) {
        #if canImport(Security)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
        query.merge(nonInteractiveKeychainOptions()) { _, new in new }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var newItem = query
        newItem[kSecValueData as String] = data
        SecItemAdd(newItem as CFDictionary, nil)
        #endif
    }

    private static func nonInteractiveKeychainOptions() -> [String: Any] {
        #if canImport(Security) && canImport(LocalAuthentication) && canImport(Darwin)
        let context = LAContext()
        context.interactionNotAllowed = true
        return [
            // AgentBar refreshes in the background; Claude quota should never
            // summon a Keychain authorization sheet just to decide visibility.
            kSecUseAuthenticationContext as String: context,
            kSecUseAuthenticationUI as String: keychainUIFailPolicy as CFString,
        ]
        #else
        return [:]
        #endif
    }

    private static func resolveKeychainUIFailPolicy() -> String {
        #if canImport(Darwin)
        let securityPath = "/System/Library/Frameworks/Security.framework/Security"
        guard let handle = dlopen(securityPath, RTLD_NOW) else {
            return "u_AuthUIF"
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "kSecUseAuthenticationUIFail") else {
            return "u_AuthUIF"
        }
        let valuePointer = symbol.assumingMemoryBound(to: CFString?.self)
        return (valuePointer.pointee as String?) ?? "u_AuthUIF"
        #else
        return "u_AuthUIF"
        #endif
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
            subscriptionType: credentials.subscriptionType,
            source: credentials.source)
    }
}
