import Foundation

/// Represents the authenticated user's profile.
/// Stored locally in Keychain; synced to backend in Phase 2.
struct UserProfile: Codable, Equatable {
    /// The stable identifier from Sign in with Apple ("sub" claim).
    let appleUserIdentifier: String

    /// Display name from first authorization. May be nil if user chose to hide it.
    let displayName: String?

    /// Email from first authorization. May be Apple's relay address or nil.
    let email: String?

    /// When the profile was first created locally.
    let createdAt: Date

    /// Greeting text for the UI — uses displayName or a generic fallback.
    var greeting: String {
        if let name = displayName { return name }
        return "Kullanıcı"
    }
}
