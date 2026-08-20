import Foundation

/// Snapshot of "what we last synced with cloud" — drives deletion diffs and LWW-Element-Set
/// semantics for the singleton UserState record's set fields.
///
/// Deletions are computed as `snapshot − local`, so this is the *only* record of what the
/// cloud still holds that local no longer does. Advancing it without having changed the
/// cloud destroys that record, and the delete is then computed as empty and skipped
/// forever. See `preservingPending(_:from:)`.
///
/// Property names are the stored JSON keys — renaming one silently orphans every snapshot
/// already on disk, which reads back as "the cloud holds nothing" and disables deletion.
struct SyncSnapshot: Codable, Equatable {
    var manualClippingIDs: Set<String> = []
    var bookOverrideTitles: Set<String> = []
    var favoriteClippingIDs: Set<String> = []
    var shownClippingIDs: Set<String> = []
    var persistedClippingIDs: Set<String> = []
    var pinnedBookTitles: Set<String> = []
    /// Hash of the singleton UserState payload at last successful sync. Lets a push
    /// skip a no-op re-save (which would otherwise bounce a silent push back to us).
    var userStateSignature: String = ""

    /// Returns this snapshot with the fields of every still-pending category carried over
    /// from `previous`.
    ///
    /// A pull finishes by recording "local now matches cloud", but that claim only covers
    /// the state the pull actually touched. A category that still owes a push has diverged
    /// on purpose, and taking local as truth for it throws away the very diff the push
    /// needs. Bootstrap pulls before it pushes, so without this a deletion that missed its
    /// push before a restart was erased on the next launch — the record survived in the
    /// user's private database with nothing left able to name it. Found in 1.1.0.
    func preservingPending(_ pending: Set<SyncPushQueue.Category>, from previous: SyncSnapshot) -> SyncSnapshot {
        var merged = self
        if pending.contains(.manualClippings) {
            merged.manualClippingIDs = previous.manualClippingIDs
        }
        if pending.contains(.bookOverrides) {
            merged.bookOverrideTitles = previous.bookOverrideTitles
        }
        if pending.contains(.userState) {
            merged.favoriteClippingIDs = previous.favoriteClippingIDs
            merged.shownClippingIDs = previous.shownClippingIDs
            merged.persistedClippingIDs = previous.persistedClippingIDs
            merged.pinnedBookTitles = previous.pinnedBookTitles
            merged.userStateSignature = previous.userStateSignature
        }
        return merged
    }
}
