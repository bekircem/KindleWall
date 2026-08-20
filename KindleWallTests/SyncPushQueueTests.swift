import XCTest
@testable import KindleWall

/// Guards the retry semantics of the CloudKit push queue.
///
/// These exist because of a real loss: the queue used to be emptied *before* the network
/// call, so a push that threw forgot what it owed. A quote deleted while the app was
/// running vanished locally, the push failed, and the deletion was never retried — the
/// record stayed in the user's private database and the sync snapshot stayed frozen at its
/// pre-deletion contents, which is how it was found.
final class SyncPushQueueTests: XCTestCase {

    /// The queue starts idle, so a launch with nothing pending makes no server call.
    func test_newQueue_isEmpty() {
        let queue = SyncPushQueue()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.pending, [])
    }

    /// Checkout hands out the work and empties the queue — marks arriving during the
    /// attempt must be tracked separately from the attempt's own set.
    func test_checkout_emptiesTheQueueAndReturnsTheWork() {
        var queue = SyncPushQueue()
        queue.markDirty(.manualClippings)
        queue.markDirty(.userState)

        let work = queue.checkout()

        XCTAssertEqual(work, [.manualClippings, .userState])
        XCTAssertTrue(queue.isEmpty)
    }

    /// The regression itself: a failed push must leave its work pending.
    func test_failedPush_keepsTheWorkPending() {
        var queue = SyncPushQueue()
        queue.markDirty(.manualClippings)

        let work = queue.checkout()
        queue.returnUnfinished(work)          // the push threw

        XCTAssertEqual(queue.pending, [.manualClippings],
                       "a deletion that failed to push must still be owed, or it is stranded in the cloud forever")
    }

    /// A category dirtied while the failed attempt was in flight survives the return —
    /// hence `formUnion` rather than an assignment.
    func test_returnUnfinished_doesNotDiscardMarksMadeDuringTheAttempt() {
        var queue = SyncPushQueue()
        queue.markDirty(.manualClippings)

        let work = queue.checkout()
        queue.markDirty(.bookOverrides)       // user edits while the push is in flight
        queue.returnUnfinished(work)          // then the push throws

        XCTAssertEqual(queue.pending, [.manualClippings, .bookOverrides])
    }

    /// A successful push keeps only what arrived mid-flight, never the work it completed.
    func test_successfulPush_leavesOnlyMidFlightWork() {
        var queue = SyncPushQueue()
        queue.markDirty(.userState)

        _ = queue.checkout()
        queue.markDirty(.manualClippings)     // arrived while the push was in flight

        XCTAssertEqual(queue.pending, [.manualClippings])
    }

    /// Bootstrap marks everything, so a divergence that opened while the app was closed —
    /// including a deletion left unpushed by an earlier failure — flushes on next launch.
    func test_markAllDirty_coversEveryCategory() {
        var queue = SyncPushQueue()
        queue.markAllDirty()

        XCTAssertEqual(queue.pending, Set(SyncPushQueue.Category.allCases))
        XCTAssertTrue(queue.pending.contains(.manualClippings))
    }

    /// Marking is idempotent: repeated notifications coalesce into one push.
    func test_markDirty_isIdempotent() {
        var queue = SyncPushQueue()
        queue.markDirty(.manualClippings)
        queue.markDirty(.manualClippings)

        XCTAssertEqual(queue.pending.count, 1)
    }

    /// Stopping the engine drops pending work rather than pushing it later.
    func test_clear_emptiesTheQueue() {
        var queue = SyncPushQueue()
        queue.markAllDirty()
        queue.clear()

        XCTAssertTrue(queue.isEmpty)
    }
}
