import AppKit
import AuthenticationServices
import Foundation
import Observation

/// Coordinates Sign in with Apple: presenting the system sheet, persisting credentials
/// to Keychain, and reflecting the result in `AuthState`. Single source of truth for
/// auth side-effects; views call into this and observe `AuthState`.
@MainActor
@Observable
final class AuthService: NSObject {
    private let authState: AuthState
    private let keychain: KeychainService
    private var currentController: ASAuthorizationController?

    init(authState: AuthState, keychain: KeychainService = KeychainService()) {
        self.authState = authState
        self.keychain = keychain
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCredentialRevoked),
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    func signIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        currentController = controller
        controller.performRequests()
    }

    func signOut() {
        keychain.delete(forKey: KeychainService.Keys.appleUserIdentifier)
        keychain.delete(forKey: KeychainService.Keys.appleUserName)
        keychain.delete(forKey: KeychainService.Keys.appleUserEmail)
        keychain.delete(forKey: KeychainService.Keys.appleUserCreatedAt)
        authState.status = .unauthenticated
    }

    /// Local-only account deletion: clears Keychain and resets state. Apple ID
    /// revocation requires a backend with a client_secret JWT, so we direct users
    /// to appleid.apple.com to unlink the app.
    func deleteAccount() {
        signOut()
    }

    func checkCredentialState() async {
        guard let userID = keychain.loadString(forKey: KeychainService.Keys.appleUserIdentifier) else {
            authState.status = .unauthenticated
            return
        }

        authState.status = .unknown
        authState.isCheckingCredential = true
        defer { authState.isCheckingCredential = false }

        let state: ASAuthorizationAppleIDProvider.CredentialState
        do {
            state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        } catch {
            authState.status = .unauthenticated
            return
        }

        switch state {
        case .authorized:
            if let profile = loadProfileFromKeychain(userID: userID) {
                authState.status = .authenticated(profile)
            } else {
                authState.status = .unauthenticated
            }
        case .revoked, .notFound, .transferred:
            signOut()
        @unknown default:
            authState.status = .unauthenticated
        }
    }

    // MARK: - Private

    @objc private func handleCredentialRevoked() {
        Task { @MainActor in
            self.signOut()
        }
    }

    private func loadProfileFromKeychain(userID: String) -> UserProfile? {
        let name = keychain.loadString(forKey: KeychainService.Keys.appleUserName)
        let email = keychain.loadString(forKey: KeychainService.Keys.appleUserEmail)
        let createdAt: Date = {
            if let iso = keychain.loadString(forKey: KeychainService.Keys.appleUserCreatedAt),
               let date = ISO8601DateFormatter().date(from: iso) {
                return date
            }
            return Date()
        }()
        return UserProfile(
            appleUserIdentifier: userID,
            displayName: name,
            email: email,
            createdAt: createdAt
        )
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        currentController = nil
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            authState.status = .unauthenticated
            return
        }

        let userID = credential.user
        keychain.save(userID, forKey: KeychainService.Keys.appleUserIdentifier)

        // fullName and email are only delivered on the FIRST authorization.
        // Preserve any previously stored values on subsequent re-auths.
        if let nameComponents = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: nameComponents).trimmingCharacters(in: .whitespaces)
            if !formatted.isEmpty {
                keychain.save(formatted, forKey: KeychainService.Keys.appleUserName)
            }
        }
        if let email = credential.email, !email.isEmpty {
            keychain.save(email, forKey: KeychainService.Keys.appleUserEmail)
        }

        let createdAt: Date
        if let iso = keychain.loadString(forKey: KeychainService.Keys.appleUserCreatedAt),
           let date = ISO8601DateFormatter().date(from: iso) {
            createdAt = date
        } else {
            createdAt = Date()
            keychain.save(ISO8601DateFormatter().string(from: createdAt),
                          forKey: KeychainService.Keys.appleUserCreatedAt)
        }

        let profile = UserProfile(
            appleUserIdentifier: userID,
            displayName: keychain.loadString(forKey: KeychainService.Keys.appleUserName),
            email: keychain.loadString(forKey: KeychainService.Keys.appleUserEmail),
            createdAt: createdAt
        )
        authState.status = .authenticated(profile)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        currentController = nil
        // Silent on user cancellation; surface other failures via state reset.
        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            return
        }
        authState.status = .unauthenticated
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let window = NSApplication.shared.windows.first(where: { !($0 is NSPanel) && $0.isVisible }) {
            return window
        }
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
