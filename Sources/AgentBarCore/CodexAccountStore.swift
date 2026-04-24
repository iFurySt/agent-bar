import Foundation

public struct CodexStoredAccount: Codable, Equatable, Sendable {
    public let id: String
    public let email: String?
    public let accountID: String?
    public let userID: String?
    public let planType: String?
    public let accountName: String?
    public let accessToken: String
    public let refreshToken: String
    public let idToken: String?
    public let lastRefresh: Date?
    public let createdAt: Date
    public let lastSeenAt: Date

    public init(
        id: String,
        email: String?,
        accountID: String?,
        userID: String?,
        planType: String?,
        accountName: String?,
        accessToken: String,
        refreshToken: String,
        idToken: String?,
        lastRefresh: Date?,
        createdAt: Date,
        lastSeenAt: Date)
    {
        self.id = id
        self.email = email
        self.accountID = accountID
        self.userID = userID
        self.planType = planType
        self.accountName = accountName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.lastRefresh = lastRefresh
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}

public struct CodexStoredAccountsSnapshot: Equatable, Sendable {
    public let currentAccountID: String?
    public let accounts: [CodexStoredAccount]

    public init(currentAccountID: String?, accounts: [CodexStoredAccount]) {
        self.currentAccountID = currentAccountID
        self.accounts = accounts
    }
}

public final class CodexAccountStore: @unchecked Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL = CodexAccountStore.defaultFileURL()) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadSnapshot() -> CodexStoredAccountsSnapshot {
        let accounts = loadEnvelope().accounts
        return CodexStoredAccountsSnapshot(currentAccountID: nil, accounts: sort(accounts, currentAccountID: nil))
    }

    public func captureCurrentAccount(
        env: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()) -> CodexStoredAccountsSnapshot
    {
        let existingAccounts = loadEnvelope().accounts

        guard let credentials = try? CodexAuthStore.load(env: env) else {
            return CodexStoredAccountsSnapshot(currentAccountID: nil, accounts: sort(existingAccounts, currentAccountID: nil))
        }

        // The current multi-account surface is for OAuth-backed logins. API key
        // mode has no stable user identity for the row list yet, so keep the
        // existing store unchanged until we add a dedicated API key treatment.
        guard !credentials.refreshToken.isEmpty || credentials.idToken != nil else {
            return CodexStoredAccountsSnapshot(currentAccountID: nil, accounts: sort(existingAccounts, currentAccountID: nil))
        }

        guard let candidate = StoredAccountCandidate(credentials: credentials) else {
            return CodexStoredAccountsSnapshot(currentAccountID: nil, accounts: sort(existingAccounts, currentAccountID: nil))
        }

        let account = candidate.account(seenAt: now, createdAt: existingAccounts.first(where: { $0.id == candidate.id })?.createdAt ?? now)
        var accountsByID = Dictionary(uniqueKeysWithValues: existingAccounts.map { ($0.id, $0) })
        accountsByID[account.id] = account
        let accounts = Array(accountsByID.values)
        save(accounts: accounts)
        return CodexStoredAccountsSnapshot(
            currentAccountID: account.id,
            accounts: sort(accounts, currentAccountID: account.id))
    }

    public static func defaultFileURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let home = env["HOME"].flatMap { raw -> URL? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URL(fileURLWithPath: trimmed, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".agentbar", isDirectory: true)
            .appendingPathComponent("accounts.json")
    }

    private func loadEnvelope() -> StoredAccountsEnvelope {
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? decoder.decode(StoredAccountsEnvelope.self, from: data)
        else {
            return StoredAccountsEnvelope(accounts: [])
        }
        return envelope
    }

    private func save(accounts: [CodexStoredAccount]) {
        do {
            let envelope = StoredAccountsEnvelope(accounts: sort(accounts, currentAccountID: nil))
            let data = try encoder.encode(envelope)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Keep the UI functional even if the account cache cannot be written.
        }
    }

    private func sort(_ accounts: [CodexStoredAccount], currentAccountID: String?) -> [CodexStoredAccount] {
        accounts.sorted { lhs, rhs in
            if currentAccountID != nil {
                let lhsCurrent = lhs.id == currentAccountID
                let rhsCurrent = rhs.id == currentAccountID
                if lhsCurrent != rhsCurrent {
                    return lhsCurrent
                }
            }
            if lhs.lastSeenAt != rhs.lastSeenAt {
                return lhs.lastSeenAt > rhs.lastSeenAt
            }
            return lhs.id < rhs.id
        }
    }
}

private struct StoredAccountsEnvelope: Codable {
    let version: Int
    let accounts: [CodexStoredAccount]

    init(accounts: [CodexStoredAccount]) {
        version = 1
        self.accounts = accounts
    }
}

private struct StoredAccountCandidate {
    let id: String
    let email: String?
    let accountID: String?
    let userID: String?
    let planType: String?
    let accountName: String?
    let credentials: CodexAuthCredentials

    init?(credentials: CodexAuthCredentials) {
        let idClaims = JWTClaims(token: credentials.idToken)
        let accessClaims = JWTClaims(token: credentials.accessToken)

        let email = Self.normalized(idClaims.string("email"))
        let accountID = Self.normalized(
            credentials.accountId ??
                idClaims.string("account_id") ??
                idClaims.string("chatgpt_account_id") ??
                accessClaims.string("account_id") ??
                accessClaims.string("chatgpt_account_id"))
        let userID = Self.normalized(
            idClaims.string("chatgpt_user_id") ??
                accessClaims.string("chatgpt_user_id") ??
                idClaims.string("sub"))
        let accountName = Self.normalized(idClaims.string("name") ?? idClaims.string("workspace_name"))
        let planType = Self.normalized(
            idClaims.string("chatgpt_plan_type") ??
                accessClaims.string("chatgpt_plan_type") ??
                idClaims.string("plan_type"))

        guard let stableID = accountID ?? email?.lowercased() ?? userID else {
            return nil
        }

        id = accountID != nil ? "chatgpt:\(stableID)" : "user:\(stableID)"
        self.email = email
        self.accountID = accountID
        self.userID = userID
        self.planType = planType
        self.accountName = accountName
        self.credentials = credentials
    }

    func account(seenAt: Date, createdAt: Date) -> CodexStoredAccount {
        CodexStoredAccount(
            id: id,
            email: email,
            accountID: accountID,
            userID: userID,
            planType: planType,
            accountName: accountName,
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            idToken: credentials.idToken,
            lastRefresh: credentials.lastRefresh,
            createdAt: createdAt,
            lastSeenAt: seenAt)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct JWTClaims {
    private let payload: [String: Any]

    init(token: String?) {
        guard let token, let payload = Self.decode(token: token) else {
            self.payload = [:]
            return
        }
        self.payload = payload
    }

    func string(_ key: String) -> String? {
        if let value = payload[key] as? String {
            return value
        }
        if let nested = payload["https://api.openai.com/auth"] as? [String: Any],
           let value = nested[key] as? String
        {
            return value
        }
        return nil
    }

    private static func decode(token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              let data = decodeBase64URL(String(segments[1])),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
