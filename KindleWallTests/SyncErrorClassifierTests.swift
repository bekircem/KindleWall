import CloudKit
import XCTest
@testable import KindleWall

/// Pins which CloudKit errors mean "the zone is gone".
///
/// `cloudKitZoneCreated` is a local flag: an app that believes it already created the zone
/// never tries again, so missing this classification leaves syncing permanently dead with no
/// recovery short of editing preferences by hand. That is not hypothetical — it happened,
/// and the app reported `Zone does not exist` on every cycle until the flag was reset.
final class SyncErrorClassifierTests: XCTestCase {

    private func ckError(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> CKError {
        CKError(_nsError: NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: userInfo))
    }

    private func partialFailure(containing inner: [CKError]) -> CKError {
        let byItem = Dictionary(uniqueKeysWithValues: inner.enumerated().map { index, error in
            (CKRecord.ID(recordName: "record-\(index)") as AnyHashable, error as Error)
        })
        return ckError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: byItem])
    }

    func test_zoneNotFound_meansMissing() {
        XCTAssertTrue(SyncErrorClassifier.meansZoneIsMissing(ckError(.zoneNotFound)))
    }

    /// The account holder deleting the app's iCloud data reports differently but leaves
    /// exactly the same nothing behind.
    func test_userDeletedZone_meansMissing() {
        XCTAssertTrue(SyncErrorClassifier.meansZoneIsMissing(ckError(.userDeletedZone)))
    }

    /// A batch operation hides the real code inside `partialErrorsByItemID`; checking only
    /// the outer code would miss every zone error that arrives through a save or delete.
    func test_partialFailure_wrappingAZoneError_meansMissing() {
        let wrapped = partialFailure(containing: [ckError(.unknownItem), ckError(.zoneNotFound)])

        XCTAssertTrue(SyncErrorClassifier.meansZoneIsMissing(wrapped),
                      "a zone error wrapped in a partial failure must still be recognised")
    }

    /// A partial failure with nothing zone-related must not trigger a rebuild — that would
    /// throw away the change token and re-upload everything over one bad record.
    func test_partialFailure_withoutAZoneError_doesNotMeanMissing() {
        let wrapped = partialFailure(containing: [ckError(.unknownItem), ckError(.serverRecordChanged)])

        XCTAssertFalse(SyncErrorClassifier.meansZoneIsMissing(wrapped))
    }

    /// Ordinary failures stay ordinary: reported, retried, never a reason to rebuild.
    func test_transientErrors_doNotMeanMissing() {
        for code in [CKError.Code.networkUnavailable, .networkFailure, .serviceUnavailable,
                     .requestRateLimited, .notAuthenticated, .changeTokenExpired] {
            XCTAssertFalse(SyncErrorClassifier.meansZoneIsMissing(ckError(code)),
                           "\(code) is not a missing zone")
        }
    }

    /// Errors from outside CloudKit must not be read as CloudKit codes — the raw values
    /// overlap and would fire a rebuild on, say, a JSON failure.
    func test_nonCloudKitError_doesNotMeanMissing() {
        let foreign = NSError(domain: NSCocoaErrorDomain,
                              code: CKError.Code.zoneNotFound.rawValue, userInfo: nil)

        XCTAssertFalse(SyncErrorClassifier.meansZoneIsMissing(foreign))
    }
}
