import Foundation
import Security

/// Anonyme Supabase-Auth über REST (kein JS-SDK). Hält das User-JWT,
/// erneuert es bei Bedarf und legt die Tokens im Keychain ab.
actor SupabaseAuth {
    static let shared = SupabaseAuth()

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?

    private let accessKey = "sb_access_token"
    private let refreshKey = "sb_refresh_token"

    private init() {
        accessToken = Keychain.read(accessKey)
        refreshToken = Keychain.read(refreshKey)
        // expiresAt ist nach Kaltstart unbekannt → wird beim ersten Zugriff erneuert.
    }

    /// Gültiges Access-Token (refresh oder anonyme Neuanmeldung bei Bedarf).
    func token() async throws -> String {
        if let token = accessToken, let exp = expiresAt, exp > Date().addingTimeInterval(60) {
            return token
        }
        if let rt = refreshToken, let token = try? await refresh(rt) {
            return token
        }
        return try await signUpAnonymous()
    }

    /// Eigene User-ID (uid = JWT 'sub') über `/auth/v1/user`. Für den Kurator-Modus.
    func userID() async throws -> String {
        let token = try await token()
        var req = URLRequest(url: URL(string: "\(SupabaseConfig.url)/auth/v1/user")!)
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw SupabaseConfig.RESTError.message("User-Abfrage fehlgeschlagen.")
        }
        struct U: Decodable { let id: String }
        return try JSONDecoder().decode(U.self, from: data).id
    }

    // MARK: - Endpunkte

    private func signUpAnonymous() async throws -> String {
        let url = URL(string: "\(SupabaseConfig.url)/auth/v1/signup")!
        return try await post(url: url, body: Data("{}".utf8))
    }

    private func refresh(_ refreshToken: String) async throws -> String {
        let url = URL(string: "\(SupabaseConfig.url)/auth/v1/token?grant_type=refresh_token")!
        let body = try JSONEncoder().encode(["refresh_token": refreshToken])
        return try await post(url: url, body: body)
    }

    private func post(url: URL, body: Data) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw SupabaseConfig.RESTError.message("Auth fehlgeschlagen (HTTP \(code)).")
        }
        let session = try JSONDecoder().decode(AuthResponse.self, from: data)
        store(session)
        return session.accessToken
    }

    private func store(_ session: AuthResponse) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        expiresAt = Date().addingTimeInterval(TimeInterval(session.expiresIn))
        Keychain.write(accessKey, session.accessToken)
        Keychain.write(refreshKey, session.refreshToken)
    }

    private struct AuthResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }
}

/// Minimaler Keychain-Wrapper für kurze String-Werte (Tokens).
enum Keychain {
    private static let service = "de.basstrainer.supabase"

    static func write(_ key: String, _ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
