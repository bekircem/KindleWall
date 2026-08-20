import XCTest
@testable import KindleWall

/// Pins the rule that keeps a pending deletion alive across a pull.
///
/// Deletions are computed as `snapshot − local`. A pull used to finish by overwriting the
/// snapshot with local unconditionally, on the reasoning that "local now matches cloud".
/// For a category still queued for a push that is false: the divergence is deliberate and
/// un-sent. Since bootstrap pulls before it pushes, a deletion whose push had not landed
/// was erased on the next launch — the diff became empty, the push skipped itself, and the
/// record stayed in the user's private database with nothing left able to name it.
final class SyncSnapshotTests: XCTestCase {

    private func snapshot(manual: Set<String> = [], overrides: Set<String> = [],
                          favorites: Set<String> = [], signature: String = "") -> SyncSnapshot {
        SyncSnapshot(
            manualClippingIDs: manual,
            bookOverrideTitles: overrides,
            favoriteClippingIDs: favorites,
            userStateSignature: signature
        )
    }

    /// The regression: five quotes deleted locally, the push not yet landed, then a pull.
    func test_pendingManualClippings_keepTheirPreviousIDsAcrossAPull() {
        let previous = snapshot(manual: ["a", "b", "c", "d", "e"])
        let local = snapshot(manual: [])          // user deleted all five

        let merged = local.preservingPending([.manualClippings], from: previous)

        XCTAssertEqual(merged.manualClippingIDs, ["a", "b", "c", "d", "e"],
                       "the pull must not erase the diff the pending push still needs")
        XCTAssertEqual(merged.manualClippingIDs.subtracting(local.manualClippingIDs).count, 5,
                       "the deletion diff must survive: snapshot − local is still five records")
    }

    /// Nothing pending means the pull's claim holds and local is recorded as-is.
    func test_nothingPending_takesLocalWholesale() {
        let previous = snapshot(manual: ["a", "b"], overrides: ["Kitap"], favorites: ["f"])
        let local = snapshot(manual: ["c"])

        XCTAssertEqual(local.preservingPending([], from: previous), local)
    }

    /// Preserving one category must not freeze the others — a pull still records what it
    /// legitimately synced.
    func test_preservingOneCategory_leavesTheOthersAtLocal() {
        let previous = snapshot(manual: ["a"], overrides: ["Eski"])
        let local = snapshot(manual: [], overrides: ["Yeni"])

        let merged = local.preservingPending([.manualClippings], from: previous)

        XCTAssertEqual(merged.manualClippingIDs, ["a"])
        XCTAssertEqual(merged.bookOverrideTitles, ["Yeni"])
    }

    /// UserState is a single record covering several set fields plus the skip-a-no-op
    /// signature; all of them travel together.
    func test_pendingUserState_preservesEverySetItCovers() {
        var previous = snapshot(favorites: ["fav"], signature: "eski")
        previous.shownClippingIDs = ["shown"]
        previous.persistedClippingIDs = ["persisted"]
        previous.pinnedBookTitles = ["Sabit"]
        let local = snapshot(favorites: [], signature: "yeni")

        let merged = local.preservingPending([.userState], from: previous)

        XCTAssertEqual(merged.favoriteClippingIDs, ["fav"])
        XCTAssertEqual(merged.shownClippingIDs, ["shown"])
        XCTAssertEqual(merged.persistedClippingIDs, ["persisted"])
        XCTAssertEqual(merged.pinnedBookTitles, ["Sabit"])
        XCTAssertEqual(merged.userStateSignature, "eski",
                       "a stale signature would let the pending UserState push skip itself as a no-op")
    }

    /// Every category the push queue knows about must be handled here, or a future one
    /// silently loses its diff the same way.
    func test_everyPushCategory_isPreservable() {
        var previous = SyncSnapshot()
        previous.manualClippingIDs = ["m"]
        previous.bookOverrideTitles = ["b"]
        previous.favoriteClippingIDs = ["u"]
        let local = SyncSnapshot()

        let merged = local.preservingPending(Set(SyncPushQueue.Category.allCases), from: previous)

        XCTAssertEqual(merged, previous,
                       "with every category pending, a pull may change nothing at all")
    }

    /// The stored JSON keys are a migration surface: a rename reads back as an empty
    /// snapshot, which means "the cloud holds nothing" and disables deletion entirely.
    func test_storedKeys_doNotChange() throws {
        var snap = SyncSnapshot()
        snap.manualClippingIDs = ["x"]
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(snap)) as? [String: Any]

        XCTAssertEqual(Set(try XCTUnwrap(json).keys), [
            "manualClippingIDs", "bookOverrideTitles", "favoriteClippingIDs",
            "shownClippingIDs", "persistedClippingIDs", "pinnedBookTitles",
            "userStateSignature",
        ])
    }
}
