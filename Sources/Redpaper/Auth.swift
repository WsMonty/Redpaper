import AppKit
import AuthenticationServices

/// Reddit OAuth for an "installed app" (no client secret).
/// Setup: create an app at https://www.reddit.com/prefs/apps, type "installed app",
/// redirect URI `redpaper://auth`, then paste its client ID below and rebuild.
@MainActor
final class Auth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let clientID = "" // ← your Reddit client ID
    static let redirectURI = "redpaper://auth"
    static var isConfigured: Bool { !clientID.isEmpty }

    @Published private(set) var signedIn = Keychain.load() != nil
    @Published private(set) var username = UserDefaults.standard.string(forKey: "redditUsername")
    private var session: ASWebAuthenticationSession?

    func signIn() async throws {
        let state = UUID().uuidString
        var c = URLComponents(string: "https://www.reddit.com/api/v1/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: Self.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "state", value: state),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "duration", value: "permanent"),
            .init(name: "scope", value: "read identity"),
        ]
        NSApp.activate()
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: "redpaper") { url, error in
                if let url { return cont.resume(returning: url) }
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    return cont.resume(throwing: CancellationError())
                }
                cont.resume(throwing: error ?? AppError("Sign-in failed."))
            }
            s.presentationContextProvider = self
            session = s
            s.start()
        }
        session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw AppError("Reddit refused sign-in: \(error)") }
        guard value("state") == state, let code = value("code") else {
            throw AppError("Sign-in response didn't match. Try again.")
        }
        try await requestToken(["grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirectURI])
        signedIn = true
        username = try? await fetchUsername()
        UserDefaults.standard.set(username, forKey: "redditUsername")
    }

    /// nil when signed out. Refreshes an expired token.
    func accessToken() async throws -> String? {
        guard let tokens = Keychain.load() else { return nil }
        return tokens.expires > Date() ? tokens.access : try await refresh()
    }

    func refresh() async throws -> String {
        guard let tokens = Keychain.load() else { throw AppError("Not signed in.") }
        do {
            return try await requestToken(["grant_type": "refresh_token", "refresh_token": tokens.refresh])
        } catch is TokenRejected {
            signOutLocally()
            throw AppError("Reddit sign-in expired. Sign in again under Settings → Account.")
        }
    }

    func signOut() {
        if let tokens = Keychain.load() {
            let req = tokenRequest("https://www.reddit.com/api/v1/revoke_token",
                                   ["token": tokens.refresh, "token_type_hint": "refresh_token"])
            Task { _ = try? await URLSession.shared.data(for: req) }
        }
        signOutLocally()
    }

    private func signOutLocally() {
        Keychain.delete()
        signedIn = false
        username = nil
        UserDefaults.standard.removeObject(forKey: "redditUsername")
    }

    @discardableResult
    private func requestToken(_ form: [String: String]) async throws -> String {
        let (data, resp) = try await URLSession.shared.data(
            for: tokenRequest("https://www.reddit.com/api/v1/access_token", form))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 400 || code == 401 { throw TokenRejected() }
        struct Response: Decodable {
            let access_token: String?
            let refresh_token: String?
            let expires_in: Double?
            let error: String?
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AppError("Reddit token request failed (\(code)).")
        }
        if r.error == "invalid_grant" { throw TokenRejected() }
        guard code == 200, let access = r.access_token else {
            throw AppError("Reddit token request failed (\(code) \(r.error ?? "")).")
        }
        guard let refresh = r.refresh_token ?? Keychain.load()?.refresh else {
            throw AppError("Reddit didn't return a refresh token.")
        }
        Keychain.save(Tokens(access: access, refresh: refresh,
                             expires: Date().addingTimeInterval((r.expires_in ?? 3600) - 60)))
        return access
    }

    private func tokenRequest(_ url: String, _ form: [String: String]) -> URLRequest {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("Basic " + Data("\(Self.clientID):".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        req.setValue(Reddit.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        req.httpBody = Data(form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }
            .joined(separator: "&").utf8)
        return req
    }

    private func fetchUsername() async throws -> String {
        guard let token = try await accessToken() else { throw AppError("Not signed in.") }
        var req = URLRequest(url: URL(string: "https://oauth.reddit.com/api/v1/me")!)
        req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Reddit.userAgent, forHTTPHeaderField: "User-Agent")
        struct Me: Decodable { let name: String }
        return try JSONDecoder().decode(Me.self, from: try await URLSession.shared.data(for: req).0).name
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() }
    }
}

private struct TokenRejected: LocalizedError {
    var errorDescription: String? { "Reddit rejected the sign-in." }
}

struct Tokens: Codable {
    let access: String
    let refresh: String
    let expires: Date
}

/// Tokens live in the login Keychain, never in UserDefaults.
enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Redpaper",
        kSecAttrAccount as String: "reddit-tokens",
    ]

    static func load() -> Tokens? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    static func save(_ tokens: Tokens) {
        delete()
        var q = query
        q[kSecValueData as String] = try? JSONEncoder().encode(tokens)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
