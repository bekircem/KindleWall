import AppKit
import Foundation
@testable import KindleWall

/// A `WallpaperManagerProtocol` that records what it was asked to do and touches neither
/// `NSWorkspace` nor the filesystem.
///
/// The rest of this test target deliberately runs against real services in temp directories —
/// that is what `DesktopWallpaperGuard` exists to make safe, and those integration tests are
/// the ones that prove a real HEIC lands on a real desktop. This fake is for the opposite
/// question: the apply *state machine* and the auto-apply *debounce*, where what matters is
/// how many applies happen and in what order, and where a real render would add seconds of
/// noise per assertion.
///
/// Keep that split. If a test cares what the wallpaper looks like, it wants the real manager.
final class FakeWallpaperManager: WallpaperManagerProtocol, @unchecked Sendable {

    // MARK: - Recorded calls

    private let lock = NSLock()
    private var _appliedURLs: [URL] = []
    private var _propagations: [Bool] = []
    private var _discarded: [URL] = []
    private var _deferredSyncCount = 0

    /// Every URL handed to `setWallpaper`, oldest first.
    var appliedURLs: [URL] { lock.withLock { _appliedURLs } }
    /// Whether each apply asked for all-Spaces propagation, aligned with `appliedURLs`.
    var propagations: [Bool] { lock.withLock { _propagations } }
    /// Files thrown away because their apply lost the race or failed.
    var discardedURLs: [URL] { lock.withLock { _discarded } }
    /// How many times the deferred all-Spaces sync actually ran.
    var deferredSyncCount: Int { lock.withLock { _deferredSyncCount } }

    var applyCount: Int { appliedURLs.count }

    // MARK: - Behaviour switches

    /// When set, `setWallpaper` throws it instead of recording an apply.
    var applyError: Error?

    // MARK: - Protocol

    private(set) var previousWallpaperURL: URL?
    var hasWallpaperOnDisk: Bool = true

    func writeWallpaperPNG(image: NSImage) throws -> URL {
        wallpaperFileURL(extension: "png")
    }

    func setWallpaper(image: NSImage) throws {
        try setWallpaper(fileURL: wallpaperFileURL(extension: "png"), propagateToAllSpaces: true)
    }

    func setWallpaper(fileURL: URL, propagateToAllSpaces: Bool) throws {
        if let applyError { throw applyError }
        lock.withLock {
            _appliedURLs.append(fileURL)
            _propagations.append(propagateToAllSpaces)
        }
    }

    func syncCurrentWallpaperToAllSpaces() {
        lock.withLock { _deferredSyncCount += 1 }
    }

    func restorePreviousWallpaper() throws {}

    func pruneWallpapers(keeping keep: [URL]) {}

    func discardPendingWallpaper(at url: URL) {
        lock.withLock { _discarded.append(url) }
    }

    func isOwnWallpaper(_ url: URL) -> Bool { true }

    func sweepOrphanedWallpapers() {}

    @discardableResult
    func repairDesktopIfWallpaperMissing() -> Bool { false }

    func isDesktopWallpaperMissing() -> Bool { false }

    func wallpaperFileURL(extension ext: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fake_\(UUID().uuidString).\(ext)")
    }

    func prepareWallpaperDirectory() throws {}
}

/// Fails every HEIC write, so the dynamic path is guaranteed to fall back to a static render.
/// Lets the "succeeded, but degraded" branch be asserted on instead of hoped for.
struct FailingHEICEncoder: HEICWallpaperEncoderProtocol {
    func write(phaseTimes: [SolarPhaseTime], to url: URL, nextFrame: (Int) -> CGImage?) throws {
        throw KindleWallError.wallpaperGenerationFailed(reason: "test")
    }
}
