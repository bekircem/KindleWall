import Foundation

/// Tracks which categories still owe a push to CloudKit.
///
/// Extracted from `CloudKitSyncService` so the retry semantics can be tested without a
/// `CKContainer` — the service builds one in `init`, which makes it unusable from a unit
/// test. The rule this type exists to enforce: work handed out by `checkout()` is only
/// forgotten once the caller reports success.
///
/// Clearing the set *before* the network call — which is what this replaced — strands a
/// pending deletion permanently. The record IDs to delete are computed as a diff against
/// the sync snapshot, and that diff is only recomputed while the category is dirty; so a
/// push that threw left the deleted records alive in the user's cloud with nothing left to
/// retry it, and the snapshot frozen at its pre-deletion contents. That shipped in 1.1.0.
struct SyncPushQueue {
    /// A category of local state that pushes as a unit.
    enum Category: Hashable, CaseIterable {
        case userState
        case manualClippings
        case bookOverrides
    }

    private(set) var pending: Set<Category> = []

    var isEmpty: Bool { pending.isEmpty }

    mutating func markDirty(_ category: Category) {
        pending.insert(category)
    }

    /// Marks every category dirty. Used at bootstrap, where local and cloud may have
    /// diverged for any reason while the app was closed.
    mutating func markAllDirty() {
        pending = Set(Category.allCases)
    }

    mutating func clear() {
        pending.removeAll()
    }

    /// Hands the pending work to a caller that is about to attempt it, emptying the queue
    /// so that marks arriving *during* the attempt are tracked separately.
    mutating func checkout() -> Set<Category> {
        defer { pending.removeAll() }
        return pending
    }

    /// Returns checked-out work after a failed attempt. Unions rather than assigns, so a
    /// category marked dirty while the failed attempt was in flight is not lost.
    mutating func returnUnfinished(_ work: Set<Category>) {
        pending.formUnion(work)
    }
}
