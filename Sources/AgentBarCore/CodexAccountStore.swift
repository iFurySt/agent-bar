import Foundation

public struct CodexAccountUsageSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let rateLimits: CodexRateLimitSnapshot
    public let isCurrent: Bool
    public let updatedAt: Date?
    public let plan: String?

    public init(
        id: String,
        label: String,
        rateLimits: CodexRateLimitSnapshot,
        isCurrent: Bool,
        updatedAt: Date?,
        plan: String? = nil)
    {
        self.id = id
        self.label = label
        self.rateLimits = rateLimits
        self.isCurrent = isCurrent
        self.updatedAt = updatedAt
        self.plan = plan
    }
}

struct CodexStoredAccount: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let credentials: CodexAuthCredentials
    let createdAt: Date
    let updatedAt: Date
}

struct CodexStoredAccountSet: Codable, Equatable, Sendable {
    let version: Int
    let accounts: [CodexStoredAccount]
}

enum CodexAccountStore {
    private static let currentVersion = 1

    static func accountsFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentbar", isDirectory: true)
            .appendingPathComponent("accounts.json")
    }

    static func load() -> [CodexStoredAccount] {
        let url = accountsFileURL()
        guard let data = try? Data(contentsOf: url),
              let set = try? JSONDecoder.agentBar.decode(CodexStoredAccountSet.self, from: data),
              set.version == currentVersion
        else {
            return []
        }
        return sanitized(set.accounts)
    }

    @discardableResult
    static func upsert(_ credentials: CodexAuthCredentials, now: Date = Date()) -> CodexStoredAccount {
        let id = credentials.stableAccountID
        var accounts = load()
        let existingIndex = accounts.firstIndex { $0.id == id }
        let account = CodexStoredAccount(
            id: id,
            label: credentials.displayLabel,
            credentials: credentials,
            createdAt: existingIndex.map { accounts[$0].createdAt } ?? now,
            updatedAt: now)

        if let existingIndex {
            accounts[existingIndex] = account
        } else {
            accounts.append(account)
        }
        save(accounts)
        return account
    }

    static func update(_ account: CodexStoredAccount) {
        var accounts = load()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        save(accounts)
    }

    private static func save(_ accounts: [CodexStoredAccount]) {
        let url = accountsFileURL()
        let set = CodexStoredAccountSet(version: currentVersion, accounts: sanitized(accounts))
        guard let data = try? JSONEncoder.agentBar.encode(set) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            #if os(macOS)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: url.path)
            #endif
        } catch {
            return
        }
    }

    private static func sanitized(_ accounts: [CodexStoredAccount]) -> [CodexStoredAccount] {
        var seen: Set<String> = []
        var result: [CodexStoredAccount] = []
        for account in accounts.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard seen.insert(account.id).inserted else { continue }
            result.append(account)
        }
        return result
    }
}

extension CodexAuthCredentials {
    var stableAccountID: String {
        if let normalized = Self.normalized(accountId) {
            return "account:\(normalized)"
        }
        if let tokenAccountID = idTokenPayload.accountID {
            return "account:\(tokenAccountID)"
        }
        if let email = idTokenPayload.email {
            return "email:\(email)"
        }
        return "token:\(Self.tokenFingerprint(refreshToken.isEmpty ? accessToken : refreshToken))"
    }

    var displayLabel: String {
        if let email = idTokenPayload.email {
            return email
        }
        if let accountID = Self.normalized(accountId) ?? idTokenPayload.accountID {
            return "Account \(accountID.suffix(6))"
        }
        return "Codex \(Self.tokenFingerprint(refreshToken.isEmpty ? accessToken : refreshToken).prefix(8))"
    }

    private var idTokenPayload: (email: String?, accountID: String?) {
        guard let idToken,
              let payload = Self.decodeJWTPayload(idToken)
        else {
            return (nil, nil)
        }

        let email = Self.normalized(payload["email"] as? String)
        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        let accountID = Self.normalized(accountId)
            ?? Self.normalized(auth?["chatgpt_account_id"] as? String)
            ?? Self.normalized(payload["chatgpt_account_id"] as? String)
        return (email, accountID)
    }

    private static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return json
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }

    private static func tokenFingerprint(_ token: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in token.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

private extension JSONDecoder {
    static var agentBar: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var agentBar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
