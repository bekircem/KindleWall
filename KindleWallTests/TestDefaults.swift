import Foundation
import XCTest

/// Creates and fully destroys throwaway `UserDefaults` suites.
///
/// `removePersistentDomain(forName:)` clears the values but leaves the backing plist behind, so
/// every test that made a suite left a file in `~/Library/Preferences`. Measured before this
/// existed: **403 orphaned `KindleWall*-*.plist` files**, the oldest ten days old — one per suite
/// per run, accumulating forever in the user's own preferences folder.
///
/// This is a small mess, but it is the same shape as two bugs this project has already paid for:
/// the wallpaper directory that grew to 13 GB, and the test run that left the desktop pointing at
/// a deleted temp file. Test infrastructure that litters the machine it runs on gets fixed at the
/// source.
///
/// Cleanup happens twice on purpose. Deleting the plist in `tearDown` races `cfprefsd`, which
/// flushes the suite on its own schedule and simply recreates the file — measured: 30 of 40 files
/// came back that way. So a bundle-level sweep runs once at the end, when no writes are pending.
enum TestDefaults {

    /// Every suite this helper makes starts with this, so the final sweep can find them all.
    private static let prefix = "KindleWallTests"

    /// One stable suite name per test class — deliberately not per test.
    ///
    /// A UUID per test meant a new plist every time any test ran, and `cfprefsd` recreates a
    /// deleted one on its own schedule, so per-test deletion loses the race (measured: 30 of 40
    /// came back, then 11). A fixed name per class bounds the whole suite to a handful of files
    /// that get reused instead of accumulating, and the end-of-run sweep clears those. XCTest
    /// runs a class's test methods serially, so reuse cannot cross-contaminate.
    static func makeSuiteName(_ label: String) -> String {
        SweepObserver.register()
        return "\(prefix)-\(label)"
    }

    /// Clears the suite's values and drops it from the search list. The plist may survive this —
    /// the sweep below is what guarantees it does not outlive the run.
    static func destroy(suiteNamed name: String, defaults: UserDefaults?) {
        defaults?.removePersistentDomain(forName: name)
        UserDefaults.standard.removeSuite(named: name)
        CFPreferencesAppSynchronize(name as CFString)
        removePlist(named: name)
    }

    fileprivate static func removePlist(named name: String) {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return }
        try? FileManager.default.removeItem(
            at: library.appendingPathComponent("Preferences/\(name).plist")
        )
    }

    /// Deletes every suite plist this bundle created, once the whole run is over.
    fileprivate final class SweepObserver: NSObject, XCTestObservation {
        /// A `static let` is initialised exactly once, lazily and thread-safely — which is all
        /// "register this observer a single time" needs. A mutable `registered` flag would be
        /// shared mutable state, and the Swift 6 mode this project runs in rejects that, rightly.
        private static let registration: Void = {
            XCTestObservationCenter.shared.addTestObserver(SweepObserver())
        }()

        static func register() { _ = registration }

        func testBundleDidFinish(_ testBundle: Bundle) {
            guard let library = FileManager.default.urls(for: .libraryDirectory,
                                                         in: .userDomainMask).first else { return }
            let preferences = library.appendingPathComponent("Preferences")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: preferences.path)) ?? []
            for name in names where name.hasPrefix(TestDefaults.prefix) && name.hasSuffix(".plist") {
                try? FileManager.default.removeItem(at: preferences.appendingPathComponent(name))
            }
        }
    }
}
