import Foundation
import XCTest
@testable import KindleWall

/// Builds `StorageService` instances that cannot touch the user's own clippings cache.
///
/// The test host is the real app, so `Constants.Paths.localClippingsFile` resolves to the real
/// `~/Library/Application Support/KindleWall/MyClippings.txt` during a test run. Every test that
/// imported a fixture wrote that fixture over the user's cached highlights, and two suites deleted
/// the file outright in `setUp` and `tearDown`. On a machine whose Kindle is not plugged in, that
/// copy is the only source the app has left — `MainViewModel` falls back to it when the
/// security-scoped bookmark cannot resolve.
///
/// This is the same lesson as `TestDefaults` (403 orphaned preference plists) and
/// `DesktopWallpaperGuard` (a desktop left pointing at a deleted temp file): test infrastructure
/// that touches the machine it runs on gets fixed at the source, not worked around.
///
/// Every cache file handed out lives under one throwaway directory that is removed when the
/// bundle finishes.
enum TestStorage {

    /// A `StorageService` whose clippings cache is a throwaway file.
    static func make(defaults: UserDefaults) -> StorageService {
        StorageService(defaults: defaults, clippingsCacheFile: makeCacheFile())
    }

    /// For the few tests that need a storage service only as a collaborator and never read a
    /// preference from it. Still isolated from the real cache.
    static func make() -> StorageService {
        StorageService(clippingsCacheFile: makeCacheFile())
    }

    /// A unique path inside the run's scratch directory. The file is not created — the code under
    /// test is what decides whether a cache comes into existence.
    static func makeCacheFile() -> URL {
        SweepObserver.register()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("MyClippings-\(UUID().uuidString).txt")
    }

    private static let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("KindleWallTests-clippings")

    /// Deletes the scratch directory once the whole run is over.
    private final class SweepObserver: NSObject, XCTestObservation {
        /// A `static let` is initialised exactly once, lazily and thread-safely — all that
        /// "register this observer a single time" needs, and legal under Swift 6's rules on
        /// shared mutable state. Same shape as `TestDefaults.SweepObserver`.
        private static let registration: Void = {
            XCTestObservationCenter.shared.addTestObserver(SweepObserver())
        }()

        static func register() { _ = registration }

        func testBundleDidFinish(_ testBundle: Bundle) {
            try? FileManager.default.removeItem(at: TestStorage.root)
        }
    }
}
