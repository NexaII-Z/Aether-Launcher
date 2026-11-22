import AuthenticationServices
import CryptoKit
import SwiftUI

struct XboxProfile: Codable, Equatable {
    var gamertag: String
    var xuid: String?
    var gamerscore: String?
    var avatarURL: String?
}

enum AccountError: LocalizedError {
    case missingClientID
    case cancelled
    case cannotStart
    case stateMismatch
    case server(String)
    case xbox(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID: return "Enter your Microsoft application (client) ID in Settings, Account first."
        case .cancelled: return "Sign-in was cancelled."
        case .cannotStart: return "iOS couldn't open the sign-in page."
        case .stateMismatch: return "The sign-in response didn't match the request. Try again."
        case .server(let message): return "Microsoft sign-in failed: \(message)"
        case .xbox(let message): return message
        case .network(let message): return "Network problem: \(message)"
        }
    }
}

/// Microsoft OAuth 2.0 (authorization code + PKCE) followed by the Xbox Live token exchange.
/// This proves who the person is on Xbox Live. It says **nothing** about whether they own Minecraft.
/// Only the refresh token is stored (Keychain); access and XSTS tokens are used once and discarded.
@MainActor
final class AccountManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case failed(String)
    }

    static let clientIDKey = "aether.msClientID"
    static let redirectScheme = "aether"
    static let redirectURI = "aether://auth"
    private static let refreshKey = "ms.refresh"
    private static let profileKey = "aether.xboxProfile"
    private static let scope = "XboxLive.signin offline_access"
    private static let authBase = "https://login.microsoftonline.com/consumers/oauth2/v2.0"

    @Published private(set) var state: State = .signedOut
    @Published private(set) var profile: XboxProfile?

    private var webSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        if Keychain.get(Self.refreshKey) != nil,
           let data = UserDefaults.standard.data(forKey: Self.profileKey),
           let cached = try? JSONDecoder().decode(XboxProfile.self, from: data) {
            profile = cached
            state = .signedIn
        }
    }

    var clientID: String { UserDefaults.standard.string(forKey: Self.clientIDKey)?.nilIfEmpty ?? "" }

    // MARK: Public

    func signIn() async {
        guard !clientID.isEmpty else { state = .failed(AccountError.missingClientID.localizedDescription); return }
        state = .signingIn
        do {
            let verifier = Self.randomString(64)
            let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
            let expectedState = Self.randomString(24)

            var components = URLComponents(string: Self.authBase + "/authorize")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
                URLQueryItem(name: "scope", value: Self.scope),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: expectedState),
                URLQueryItem(name: "prompt", value: "select_account")
            ]
            let callback = try await authenticate(with: components.url!)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value {
                let detail = items.first(where: { $0.name == "error_description" })?.value ?? error
                throw AccountError.server(detail)
            }
            guard items.first(where: { $0.name == "state" })?.value == expectedState else { throw AccountError.stateMismatch }
            guard let code = items.first(where: { $0.name == "code" })?.value else { throw AccountError.server("no authorization code returned") }

            let tokens = try await tokenRequest([
                "client_id": clientID, "grant_type": "authorization_code", "code": code,
                "redirect_uri": Self.redirectURI, "code_verifier": verifier, "scope": Self.scope
            ])
            try await finish(with: tokens)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Re-runs the token exchange with the stored refresh token to update the profile.
    func refresh() async {
        guard let refreshToken = Keychain.get(Self.refreshKey) else { state = .signedOut; return }
        guard !clientID.isEmpty else { state = .failed(AccountError.missingClientID.localizedDescription); return }
        state = .signingIn
        do {
            let tokens = try await tokenRequest([
                "client_id": clientID, "grant_type": "refresh_token",
                "refresh_token": refreshToken, "scope": Self.scope
            ])
            try await finish(with: tokens)
        } catch {
            state = .failed(error.localizedDescription + " You may need to sign in again.")
        }
    }

    func signOut() {
        Keychain.delete(Self.refreshKey)
        UserDefaults.standard.removeObject(forKey: Self.profileKey)
        profile = nil
        state = .signedOut
    }

    // MARK: Flow

    private struct Tokens {
        let access: String
        let refresh: String?
    }

    private func finish(with tokens: Tokens) async throws {
        let profile = try await Self.xboxProfile(accessToken: tokens.access)
        if let refresh = tokens.refresh { Keychain.set(refresh, for: Self.refreshKey) }
        if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: Self.profileKey) }
        self.profile = profile
        state = .signedIn
    }

    private func authenticate(with url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.redirectScheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                    continuation.resume(throwing: AccountError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AccountError.cancelled)
                }
            }
            session.presentationContextProvider = self
            webSession = session
            if !session.start() { continuation.resume(throwing: AccountError.cannotStart) }
        }
    }

    private func tokenRequest(_ form: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: URL(string: Self.authBase + "/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await Self.send(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let access = json?["access_token"] as? String else {
            let detail = json?["error_description"] as? String ?? json?["error"] as? String ?? "unexpected response"
            throw AccountError.server(detail.components(separatedBy: "\r\n").first ?? detail)
        }
        return Tokens(access: access, refresh: json?["refresh_token"] as? String)
    }

    private nonisolated static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw AccountError.network(error.localizedDescription)
        }
    }

    private nonisolated static func postJSON(_ url: String, body: [String: Any], headers: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await send(request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private nonisolated static func userHash(_ json: [String: Any]?) -> String? {
        let claims = json?["DisplayClaims"] as? [String: Any]
        return ((claims?["xui"] as? [[String: Any]])?.first)?["uhs"] as? String
    }

    private nonisolated static func xboxProfile(accessToken: String) async throws -> XboxProfile {
        let (xblData, xblStatus) = try await postJSON(
            "https://user.auth.xboxlive.com/user/authenticate",
            body: ["Properties": ["AuthMethod": "RPS", "SiteName": "user.auth.xboxlive.com", "RpsTicket": "d=\(accessToken)"],
                   "RelyingParty": "http://auth.xboxlive.com", "TokenType": "JWT"],
            headers: ["x-xbl-contract-version": "1"])
        let xbl = (try? JSONSerialization.jsonObject(with: xblData)) as? [String: Any]
        guard xblStatus == 200, let xblToken = xbl?["Token"] as? String else {
            throw AccountError.xbox("Xbox Live rejected the Microsoft token (HTTP \(xblStatus)).")
        }

        let (xstsData, xstsStatus) = try await postJSON(
            "https://xsts.auth.xboxlive.com/xsts/authorize",
            body: ["Properties": ["SandboxId": "RETAIL", "UserTokens": [xblToken]],
                   "RelyingParty": "http://xboxlive.com", "TokenType": "JWT"],
            headers: ["x-xbl-contract-version": "1"])
        let xsts = (try? JSONSerialization.jsonObject(with: xstsData)) as? [String: Any]
        guard xstsStatus == 200, let xstsToken = xsts?["Token"] as? String, let hash = userHash(xsts) else {
            throw AccountError.xbox(describeXSTS(code: xsts?["XErr"] as? Int, status: xstsStatus))
        }

        var request = URLRequest(url: URL(string: "https://profile.xboxlive.com/users/me/profile/settings?settings=Gamertag,Gamerscore,GameDisplayPicRaw")!)
        request.setValue("XBL3.0 x=\(hash);\(xstsToken)", forHTTPHeaderField: "Authorization")
        request.setValue("3", forHTTPHeaderField: "x-xbl-contract-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200, let user = (json?["profileUsers"] as? [[String: Any]])?.first else {
            throw AccountError.xbox("Couldn't read the Xbox profile (HTTP \(status)).")
        }
        let settings = (user["settings"] as? [[String: Any]]) ?? []
        func value(_ id: String) -> String? { settings.first { $0["id"] as? String == id }?["value"] as? String }
        guard let gamertag = value("Gamertag") else { throw AccountError.xbox("This Xbox profile has no gamertag.") }
        return XboxProfile(gamertag: gamertag, xuid: user["id"] as? String,
                           gamerscore: value("Gamerscore"), avatarURL: value("GameDisplayPicRaw"))
    }

    private nonisolated static func describeXSTS(code: Int?, status: Int) -> String {
        switch code {
        case 2148916233: return "This Microsoft account has no Xbox profile. Create one at xbox.com, then sign in again."
        case 2148916235: return "Xbox Live isn't available in this account's country or region."
        case 2148916236, 2148916237: return "This account needs adult verification before it can use Xbox Live."
        case 2148916238: return "This is a child account. A family organiser must add it to a Microsoft family group first."
        case .some(let other): return "Xbox Live refused the request (error \(other))."
        case .none: return "Xbox Live refused the request (HTTP \(status))."
        }
    }

    // MARK: Helpers

    private static func randomString(_ length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] })
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}
