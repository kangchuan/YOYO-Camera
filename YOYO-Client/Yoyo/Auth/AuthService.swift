import AuthenticationServices
import Foundation

// MARK: - User Model

struct User: Codable {
    let id: Int
    let appleUserId: String
    let email: String?
    let fullName: String?
    let credits: Int?
    let subscriptionStatus: Int? // 0: free, 1: pro
}

// MARK: - Auth Response

private struct AuthResponse: Codable {
    let user: User
    let token: String
}

private struct UpdateNameResponse: Codable {
    let fullName: String
}

// MARK: - Auth Service

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var currentUser: User?
    @Published private(set) var authToken: String?
    @Published private(set) var isLoading = false

    /// 服务地址统一从 `ServiceEndpoints` 取，可在「设置 → 开发者模式 → 服务地址」中修改
    private var baseURL: String { ServiceEndpoints.shared.apiBaseURL }

    private let userCacheKey = "cachedUser"
    private let tokenCacheKey = "cachedToken"
    private let pendingUserInfoKeyPrefix = "pendingUserInfo_"

    // MARK: - Profile fetch (TTL + backoff)

    /// How stale `currentUser` is allowed to be before we re-fetch on foreground.
    /// Five minutes is enough to absorb a quick "lock / unlock" cycle without
    /// hammering the server.
    private static let profileTTL: TimeInterval = 300

    /// Failure backoff: cap at 30 minutes so a single bad request does not
    /// lock the UI out of profile refresh forever.
    private static let profileBackoffBase: TimeInterval = 5
    private static let profileBackoffCap: TimeInterval = 30 * 60

    private var lastProfileFetchAt: Date?
    private var lastProfileFailureAt: Date?
    private var consecutiveProfileFailures: Int = 0
    private let keychain: KeychainStoring = KeychainStore.instance

    private struct PendingUserInfo: Codable {
        let fullName: String?
        let email: String?
    }

    private init() {
        // One-shot migration: the JWT was previously stored in plain
        // `UserDefaults`. Move it to the keychain on first launch and clear
        // the legacy slot so we never persist the same secret twice.
        keychain.migrateFromLegacyDefaults(key: tokenCacheKey, defaults: .standard)
        loadCachedUser()
    }

    // MARK: - Public Methods

    /// Re-fetch the user profile from the server.
    ///
    /// TTL: skips the round trip if we already fetched within `profileTTL`.
    /// Backoff: on consecutive failures, the next call has to wait at least
    /// `5s * 2^n` (capped at 30 minutes) before trying again. Both are
    /// reset by a successful response.
    ///
    /// Note: callers in `YoyoApp` still invoke this on `.active`, so this is
    /// the single source of truth for "should we hit `/api/user` again?".
    /// No parallel state was added elsewhere.
    func fetchUserProfile() async {
        guard authToken != nil else { return }

        // Backoff gate: don't hammer the server after recent failures.
        if let lastFailure = lastProfileFailureAt,
           let nextAllowed = nextBackoffDate(from: lastFailure),
           Date() < nextAllowed
        {
            debugLog("⏳ Skipping fetchUserProfile (backoff until \(nextAllowed))")
            return
        }

        // TTL gate: avoid redundant fetches within the freshness window.
        if let lastSuccess = lastProfileFetchAt,
           Date().timeIntervalSince(lastSuccess) < Self.profileTTL
        {
            debugLog("⏳ Skipping fetchUserProfile (TTL fresh)")
            return
        }

        guard let url = URL(string: "\(baseURL)/api/user") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken ?? "")", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 401 {
                debugLog("⚠️ Token expired or invalid, signing out...")
                await MainActor.run { [weak self] in self?.signOut() }
                return
            }

            guard httpResponse.statusCode == 200 else {
                debugLog("❌ Fetch user profile failed: \(httpResponse.statusCode)")
                await MainActor.run { [weak self] in self?.recordProfileFailure() }
                return
            }

            if let responseString = String(data: data, encoding: .utf8) {
                debugLog("📥 Fetch user profile response: \(responseString)")
            }

            let user = try JSONDecoder().decode(User.self, from: data)

            await MainActor.run {
                self.currentUser = user
                self.cacheUser(user)
                self.recordProfileSuccess()
                debugLog("✅ User profile updated: \(user.fullName ?? "Unknown")")
            }
        } catch {
            debugLog("❌ Fetch user profile error: \(error)")
            await MainActor.run { [weak self] in self?.recordProfileFailure() }
        }
    }

    /// Public hook used by debug tooling and tests to reset the TTL/backoff
    /// state without affecting the cached user. Normal callers should not
    /// need this — a successful `fetchUserProfile` already clears it.
    func resetProfileFetchState() {
        lastProfileFetchAt = nil
        lastProfileFailureAt = nil
        consecutiveProfileFailures = 0
    }

    private func recordProfileSuccess() {
        lastProfileFetchAt = Date()
        lastProfileFailureAt = nil
        consecutiveProfileFailures = 0
    }

    private func recordProfileFailure() {
        lastProfileFailureAt = Date()
        consecutiveProfileFailures += 1
    }

    private func nextBackoffDate(from failure: Date) -> Date? {
        guard consecutiveProfileFailures > 0 else { return nil }
        let exponent = min(consecutiveProfileFailures - 1, 6) // cap 2^6 = 64x
        let interval = min(Self.profileBackoffBase * pow(2.0, Double(exponent)), Self.profileBackoffCap)
        return failure.addingTimeInterval(interval)
    }

    func syncSubscription(originalTransactionId: String) async throws {
        guard let token = authToken else {
            // Check if user is logged in, if not, we can't sync to a user account
            debugLog("⚠️ Cannot sync subscription: User not logged in")
            return
        }

        guard let url = URL(string: "\(baseURL)/api/user/subscribe") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["originalTransactionId": originalTransactionId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("❌ Sync Subscription Error (\(httpResponse.statusCode)): \(errorMessage)")
            throw AuthError.serverError(httpResponse.statusCode)
        }

        struct SubscribeResponse: Codable {
            let subscriptionStatus: Int
            let subscriptionEndDate: String?
            let credits: Int?
        }

        let subResponse = try JSONDecoder().decode(SubscribeResponse.self, from: data)

        await MainActor.run {
            if let currentUser = self.currentUser {
                let updatedUser = User(
                    id: currentUser.id,
                    appleUserId: currentUser.appleUserId,
                    email: currentUser.email,
                    fullName: currentUser.fullName,
                    credits: subResponse.credits ?? currentUser.credits,
                    subscriptionStatus: subResponse.subscriptionStatus
                )
                self.currentUser = updatedUser
                self.cacheUser(updatedUser)
            }
        }
    }

    func signInWithApple(authorization: ASAuthorization) async {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            debugLog("❌ Invalid credential type")
            return
        }

        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            debugLog("❌ Missing identity token")
            return
        }

        let userIdentifier = credential.user

        // Build the full name
        var fullName: String?
        if let nameComponents = credential.fullName {
            let parts = [nameComponents.familyName, nameComponents.givenName].compactMap { $0 }
            if !parts.isEmpty {
                fullName = parts.joined()
            }
        }

        var email = credential.email

        // If Apple provides the info (usually only on first authorization), cache it locally first
        // This prevents the info from being lost if a network issue blocks backend sync and Apple does not provide it again later
        if fullName != nil || email != nil {
            cachePendingUserInfo(userIdentifier: userIdentifier, fullName: fullName, email: email)
        }

        // If Apple does not provide the info, try reading previously cached values from local storage
        if fullName == nil || email == nil {
            if let cached = getPendingUserInfo(userIdentifier: userIdentifier) {
                fullName = fullName ?? cached.fullName
                email = email ?? cached.email
                debugLog("ℹ️ Using cached pending user info for \(userIdentifier)")
            }
        }

        debugLog("🔵 Sending auth request to server...")
        debugLog("   userIdentifier: \(userIdentifier)")
        debugLog("   fullName: \(fullName ?? "nil")")
        debugLog("   email: \(email ?? "nil")")

        isLoading = true
        defer { isLoading = false }

        do {
            let (user, token) = try await authenticateWithServer(
                identityToken: identityToken,
                userIdentifier: userIdentifier,
                fullName: fullName,
                email: email
            )

            // Clear the pending info after it has been synced to the backend and a token has been obtained
            clearPendingUserInfo(userIdentifier: userIdentifier)

            currentUser = user
            authToken = token
            cacheUser(user)
            cacheToken(token)
            debugLog("✅ User authenticated: \(user)")
        } catch {
            debugLog("❌ Auth error: \(error)")
            // Keep the cache on authentication failure so the next sign-in retry can attempt syncing again
        }
    }

    func signOut() {
        currentUser = nil
        authToken = nil
        clearCachedUser()
    }

    func deleteAccount() async throws {
        guard let token = authToken else {
            throw AuthError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)/api/user") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("❌ Server error (\(httpResponse.statusCode)): \(errorMessage)")
            throw AuthError.serverError(httpResponse.statusCode)
        }

        // Sign out after successful deletion
        signOut()
        debugLog("✅ Account deleted successfully")
    }

    func updateCredits(_ newCredits: Int) {
        guard var user = currentUser else { return }

        // Create a new `User` instance because it is a struct and its properties are `let`
        user = User(
            id: user.id,
            appleUserId: user.appleUserId,
            email: user.email,
            fullName: user.fullName,
            credits: newCredits,
            subscriptionStatus: user.subscriptionStatus
        )

        currentUser = user
        cacheUser(user)
        debugLog("✅ Credits updated: \(newCredits)")
    }

    func updateName(_ newName: String) async throws {
        guard let token = authToken else {
            throw AuthError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)/api/user") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["fullName": newName]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("❌ Server error (\(httpResponse.statusCode)): \(errorMessage)")
            throw AuthError.serverError(httpResponse.statusCode)
        }

        if let responseString = String(data: data, encoding: .utf8) {
            debugLog("✅ Server response: \(responseString)")
        }

        let updateResponse = try JSONDecoder().decode(UpdateNameResponse.self, from: data)
        let newName = updateResponse.fullName

        await MainActor.run {
            if let currentUser = self.currentUser {
                let updatedUser = User(
                    id: currentUser.id,
                    appleUserId: currentUser.appleUserId,
                    email: currentUser.email,
                    fullName: newName,
                    credits: currentUser.credits,
                    subscriptionStatus: currentUser.subscriptionStatus
                )
                self.currentUser = updatedUser
                self.cacheUser(updatedUser)
            }
        }

        debugLog("✅ Name updated: \(newName)")
    }

    // MARK: - Debug

    func debugSetProStatus(isPro: Bool) {
        guard let user = currentUser else { return }

        let updatedUser = User(
            id: user.id,
            appleUserId: user.appleUserId,
            email: user.email,
            fullName: user.fullName,
            credits: user.credits,
            subscriptionStatus: isPro ? 1 : 0
        )

        currentUser = updatedUser
        // Note: We intentionally do not cache this debug state so it resets on relaunch
        debugLog("🔧 Debug: Pro status set to \(isPro)")
    }

    var isLoggedIn: Bool {
        currentUser != nil
    }

    // MARK: - 二次开发调试

    /// 与 `ServiceEndpointSettingsView` 共用同一个键
    private static let bypassAuthKey = "debug.bypassAuth"

    /// 服务层统一使用的 Token。
    /// 正常情况下就是登录态 Token；开启「跳过登录校验」后，未登录时回落到占位值，
    /// 便于在免费账号（无 Sign in with Apple）环境下联调自建后端。
    var effectiveAuthToken: String? {
        if let authToken { return authToken }
        return UserDefaults.standard.bool(forKey: Self.bypassAuthKey) ? "debug-bypass-token" : nil
    }

    // MARK: - Private Methods

    private func authenticateWithServer(
        identityToken: String,
        userIdentifier: String,
        fullName: String?,
        email: String?
    ) async throws -> (User, String) {
        guard let url = URL(string: "\(baseURL)/api/auth/apple") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "identityToken": identityToken,
            "userIdentifier": userIdentifier,
        ]
        if let fullName { body["fullName"] = fullName }
        if let email { body["email"] = email }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("❌ Server error (\(httpResponse.statusCode)): \(errorMessage)")
            throw AuthError.serverError(httpResponse.statusCode)
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        return (authResponse.user, authResponse.token)
    }

    // MARK: - Cache

    private func cacheUser(_ user: User) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userCacheKey)
        }
    }

    private func cacheToken(_ token: String) {
        // JWT secret: persist via Keychain (`kSecClassGenericPassword`)
        // rather than `UserDefaults` so it never lands in a plain plist.
        keychain.writeString(token, forKey: tokenCacheKey)
    }

    private func loadCachedUser() {
        if let data = UserDefaults.standard.data(forKey: userCacheKey),
           let user = try? JSONDecoder().decode(User.self, from: data)
        {
            currentUser = user
        }
        // Token comes from the keychain. If migration did not run yet
        // (e.g. user wipes UserDefaults first), we fall back to the legacy
        // slot once — but the next write will move it across.
        if let token = keychain.readString(forKey: tokenCacheKey) {
            authToken = token
        } else if let legacy = UserDefaults.standard.string(forKey: tokenCacheKey) {
            authToken = legacy
            cacheToken(legacy) // promote to keychain
            UserDefaults.standard.removeObject(forKey: tokenCacheKey)
        }
    }

    private func clearCachedUser() {
        UserDefaults.standard.removeObject(forKey: userCacheKey)
        UserDefaults.standard.removeObject(forKey: tokenCacheKey)
        keychain.delete(forKey: tokenCacheKey)
    }

    private func cachePendingUserInfo(userIdentifier: String, fullName: String?, email: String?) {
        let info = PendingUserInfo(fullName: fullName, email: email)
        if let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: pendingUserInfoKeyPrefix + userIdentifier)
        }
    }

    private func getPendingUserInfo(userIdentifier: String) -> PendingUserInfo? {
        guard let data = UserDefaults.standard.data(forKey: pendingUserInfoKeyPrefix + userIdentifier),
              let info = try? JSONDecoder().decode(PendingUserInfo.self, from: data)
        else {
            return nil
        }
        return info
    }

    private func clearPendingUserInfo(userIdentifier: String) {
        UserDefaults.standard.removeObject(forKey: pendingUserInfoKeyPrefix + userIdentifier)
    }
}

// MARK: - Auth Error

enum AuthError: Error {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case notAuthenticated
}
