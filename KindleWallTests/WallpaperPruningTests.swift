import XCTest
@testable import KindleWall

final class WallpaperPruningTests: XCTestCase {
    /// A fresh empty directory per test, so no test can see another's files.
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KindleWallTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Writes a placeholder file and returns its URL.
    @discardableResult
    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    private func remainingFileNames() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: tempDir.path))
    }

    /// Pruning deletes on a background queue — doing it inline froze the window on the first
    /// launch after pruning shipped, when there were 604 files to remove. Tests therefore wait
    /// for the directory to settle instead of reading it immediately.
    private func waitForRemainingFiles(_ expected: Set<String>,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(10)
        var last: Set<String> = []
        while Date() < deadline {
            last = try remainingFileNames()
            if last == expected { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(last, expected, file: file, line: line)
    }

    private func makeManager() -> WallpaperManager {
        WallpaperManager(storageService: StorageService(), wallpapersDirectory: tempDir)
    }

    func test_setUp_createsEmptyDirectory() throws {
        XCTAssertEqual(try remainingFileNames(), [])
    }

    // MARK: - Pruning

    func test_prune_deletesEverythingExceptTheKeptFile() throws {
        try makeFile("old_a.png")
        try makeFile("old_b.png")
        let keep = try makeFile("active.heic")

        makeManager().pruneWallpapers(keeping: [keep])

        try waitForRemainingFiles(["active.heic"])
    }

    func test_prune_keepsEveryUrlPassedIn() throws {
        try makeFile("old.png")
        let a = try makeFile("a.png")
        let b = try makeFile("b.png")

        makeManager().pruneWallpapers(keeping: [a, b])

        try waitForRemainingFiles(["a.png", "b.png"])
    }

    func test_prune_onMissingDirectory_doesNotCrash() throws {
        try FileManager.default.removeItem(at: tempDir)
        makeManager().pruneWallpapers(keeping: [])   // must be a no-op, not a crash
    }

    // MARK: - Ownership

    func test_isOwnWallpaper_trueForFileInsideOurDirectory() throws {
        let mine = try makeFile("kindlewall_123.png")
        XCTAssertTrue(makeManager().isOwnWallpaper(mine))
    }

    func test_isOwnWallpaper_falseForFileOutsideOurDirectory() {
        let theirs = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Mac Blue.heic")
        XCTAssertFalse(makeManager().isOwnWallpaper(theirs))
    }

    // MARK: - Launch sweep

    func test_sweep_keepsOnlyTheWallpaperCurrentlyOnTheDesktop() throws {
        try makeFile("orphan_a.png")
        try makeFile("orphan_b.png")
        let active = try makeFile("active.png")

        // Stand in for "what the desktop currently points at" without touching NSWorkspace.
        makeManager().sweepOrphanedWallpapers(currentDesktopURL: active)

        try waitForRemainingFiles(["active.png"])
    }

    func test_sweep_whenDesktopWallpaperIsNotOurs_deletesEverything() throws {
        try makeFile("orphan_a.png")
        try makeFile("orphan_b.png")
        let foreign = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Mac Blue.heic")

        makeManager().sweepOrphanedWallpapers(currentDesktopURL: foreign)

        try waitForRemainingFiles([])
    }

    /// The bug this guards against actually happened: the desktop was pointing at one of our
    /// files that had already been deleted, so the sweep decided nothing was worth keeping and
    /// emptied the directory. The result was a blank desktop with no wallpaper left to restore.
    func test_sweep_whenDesktopPointsAtOneOfOurDeletedFiles_keepsTheNewestSurvivor() throws {
        try makeFile("old.png")
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let newest = try makeFile("newest.png")
        let deletedButStillReferenced = tempDir.appendingPathComponent("gone.png")

        makeManager().sweepOrphanedWallpapers(currentDesktopURL: deletedButStillReferenced)

        try waitForRemainingFiles([newest.lastPathComponent])
    }

    func test_sweep_neverEmptiesTheDirectoryWhileTheDesktopStillNeedsUs() throws {
        try makeFile("a.png")
        try makeFile("b.png")
        let stale = tempDir.appendingPathComponent("missing.png")

        makeManager().sweepOrphanedWallpapers(currentDesktopURL: stale)

        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertFalse(try remainingFileNames().isEmpty,
                       "masaüstü hâlâ bize bağlıyken dizin tamamen boşaltılmamalı")
    }

    func test_isOwnWallpaper_falseForSiblingDirectoryWithSharedPrefix() {
        // "…/wallpapers-backup/x.png" must not count as being inside "…/wallpapers/".
        let sibling = tempDir.deletingLastPathComponent()
            .appendingPathComponent(tempDir.lastPathComponent + "-backup")
            .appendingPathComponent("x.png")
        XCTAssertFalse(makeManager().isOwnWallpaper(sibling))
    }
}
