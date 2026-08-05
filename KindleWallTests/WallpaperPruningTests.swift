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

        XCTAssertEqual(try remainingFileNames(), ["active.heic"])
    }

    func test_prune_keepsEveryUrlPassedIn() throws {
        try makeFile("old.png")
        let a = try makeFile("a.png")
        let b = try makeFile("b.png")

        makeManager().pruneWallpapers(keeping: [a, b])

        XCTAssertEqual(try remainingFileNames(), ["a.png", "b.png"])
    }

    func test_prune_onMissingDirectory_doesNotCrash() throws {
        try FileManager.default.removeItem(at: tempDir)
        makeManager().pruneWallpapers(keeping: [])   // must be a no-op, not a crash
    }
}
