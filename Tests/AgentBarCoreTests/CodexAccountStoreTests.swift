import Foundation
import XCTest
@testable import AgentBarCore

final class CodexAccountStoreTests: XCTestCase {
    func testCaptureCurrentAccountPersistsAndSortsMostRecentFirst() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexHome = root.appendingPathComponent("codex-home", isDirectory: true)
        let storeURL = root.appendingPathComponent("accounts.json")
        let env = ["CODEX_HOME": codexHome.path]
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = CodexAccountStore(fileURL: storeURL)
        let firstAccessToken = try writeAuthFile(
            at: codexHome.appendingPathComponent("auth.json"),
            email: "alpha@example.com",
            accountID: "acc-alpha",
            accessToken: "access-alpha",
            refreshToken: "refresh-alpha")

        let firstSeen = Date(timeIntervalSince1970: 1_000)
        let firstSnapshot = store.captureCurrentAccount(env: env, now: firstSeen)
        XCTAssertEqual(firstSnapshot.accounts.count, 1)
        XCTAssertEqual(firstSnapshot.currentAccountID, "chatgpt:acc-alpha")
        XCTAssertEqual(firstSnapshot.accounts.first?.email, "alpha@example.com")
        XCTAssertEqual(firstSnapshot.accounts.first?.accessToken, firstAccessToken)

        _ = try writeAuthFile(
            at: codexHome.appendingPathComponent("auth.json"),
            email: "beta@example.com",
            accountID: "acc-beta",
            accessToken: "access-beta",
            refreshToken: "refresh-beta")

        let secondSeen = Date(timeIntervalSince1970: 2_000)
        let secondSnapshot = store.captureCurrentAccount(env: env, now: secondSeen)
        XCTAssertEqual(secondSnapshot.accounts.map(\.id), ["chatgpt:acc-beta", "chatgpt:acc-alpha"])
        XCTAssertEqual(secondSnapshot.currentAccountID, "chatgpt:acc-beta")
    }

    func testCaptureCurrentAccountUpsertsExistingIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexHome = root.appendingPathComponent("codex-home", isDirectory: true)
        let storeURL = root.appendingPathComponent("accounts.json")
        let env = ["CODEX_HOME": codexHome.path]
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = CodexAccountStore(fileURL: storeURL)
        let authURL = codexHome.appendingPathComponent("auth.json")
        _ = try writeAuthFile(
            at: authURL,
            email: "alpha@example.com",
            accountID: "acc-alpha",
            accessToken: "access-alpha-v1",
            refreshToken: "refresh-alpha-v1")
        _ = store.captureCurrentAccount(env: env, now: Date(timeIntervalSince1970: 1_000))

        let updatedAccessToken = try writeAuthFile(
            at: authURL,
            email: "alpha@example.com",
            accountID: "acc-alpha",
            accessToken: "access-alpha-v2",
            refreshToken: "refresh-alpha-v2")
        let snapshot = store.captureCurrentAccount(env: env, now: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(snapshot.accounts.count, 1)
        XCTAssertEqual(snapshot.accounts.first?.accessToken, updatedAccessToken)
        XCTAssertEqual(snapshot.accounts.first?.refreshToken, "refresh-alpha-v2")
        XCTAssertEqual(snapshot.accounts.first?.createdAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(snapshot.accounts.first?.lastSeenAt, Date(timeIntervalSince1970: 2_000))
    }

    private func writeAuthFile(
        at url: URL,
        email: String,
        accountID: String,
        accessToken: String,
        refreshToken: String) throws -> String
    {
        let accessJWT = jwt([
            "https://api.openai.com/auth": [
                "account_id": accountID,
                "chatgpt_plan_type": "pro",
            ],
            "sub": "user-\(accountID)",
            "token_version": accessToken,
        ])
        let idJWT = jwt([
            "email": email,
            "name": email.replacingOccurrences(of: "@example.com", with: "").capitalized,
        ])

        let payload: [String: Any] = [
            "tokens": [
                "access_token": accessJWT,
                "refresh_token": refreshToken,
                "id_token": idJWT,
                "account_id": accountID,
            ],
            "last_refresh": "2026-04-24T08:00:00Z",
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return accessJWT
    }

    private func jwt(_ payload: [String: Any]) -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let headerData = try! JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return [
            base64url(headerData),
            base64url(payloadData),
            "signature",
        ].joined(separator: ".")
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
