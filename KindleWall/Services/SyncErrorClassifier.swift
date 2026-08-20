import CloudKit
import Foundation

/// Classifies the CloudKit errors the sync engine has to *act* on rather than merely report.
enum SyncErrorClassifier {

    /// True when the server says the app's custom record zone is gone.
    ///
    /// `cloudKitZoneCreated` is a local flag, so an app that believes it already created the
    /// zone never tries again: every later sync fails with this same error and syncing stays
    /// dead until someone edits preferences by hand. The zone can vanish without the app
    /// doing anything — the user deleting the app's iCloud data, an account reset, a
    /// container reset in the CloudKit console. Recovering means noticing this specific
    /// error, which is why it is worth naming rather than lumping in with "sync failed".
    ///
    /// Zone errors also arrive wrapped: a batch operation reports `.partialFailure` and keeps
    /// the real code in `partialErrorsByItemID`, so checking only the outer code misses them.
    static func meansZoneIsMissing(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if isMissingZoneCode(ckError.code) { return true }

        guard ckError.code == .partialFailure,
              let partials = ckError.partialErrorsByItemID
        else { return false }

        return partials.values.contains { inner in
            guard let innerCKError = inner as? CKError else { return false }
            return isMissingZoneCode(innerCKError.code)
        }
    }

    /// `userDeletedZone` is the same situation reported differently: the server distinguishes
    /// "never existed / already gone" from "the account holder deleted it", and neither leaves
    /// anything to sync against.
    private static func isMissingZoneCode(_ code: CKError.Code) -> Bool {
        code == .zoneNotFound || code == .userDeletedZone
    }
}
