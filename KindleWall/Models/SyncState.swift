import Foundation
import Observation

/// Reactive sync status exposed to the UI (AccountView). Owned by `KindleWallApp`,
/// mutated by `CloudKitSyncService`, observed via SwiftUI environment.
@MainActor
@Observable
final class SyncState {
    enum Status: Equatable {
        /// iCloud account unavailable or user signed out — sync engine is dormant.
        case disabled(reason: String)
        /// Engine is running, last sync (if any) completed successfully.
        case idle
        /// A push or pull is in flight right now.
        case syncing
        /// Last sync failed; user-facing message held in associated value.
        case error(String)
    }

    var status: Status = .disabled(reason: "Hesabınızla giriş yapın")
    var lastSyncedAt: Date?
}
