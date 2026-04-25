import Foundation
import Observation

/// Tracks the user's authentication state across the app.
/// Injected via SwiftUI environment from KindleWallApp.
@Observable
final class AuthState {
    /// The current authentication status.
    var status: Status = .unauthenticated

    /// Whether a credential check or sign-in is in progress.
    var isCheckingCredential: Bool = false

    /// Whether the user is currently authenticated.
    var isAuthenticated: Bool {
        if case .authenticated = status { return true }
        return false
    }

    /// The current user profile, if authenticated.
    var currentUser: UserProfile? {
        if case .authenticated(let profile) = status { return profile }
        return nil
    }

    /// Discrete authentication states.
    enum Status: Equatable {
        /// App just launched, checking stored credential.
        case unknown
        /// No valid credential found.
        case unauthenticated
        /// User is signed in with a valid profile.
        case authenticated(UserProfile)
    }
}
