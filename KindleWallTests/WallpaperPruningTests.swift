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

    func test_setUp_createsEmptyDirectory() throws {
        XCTAssertEqual(try remainingFileNames(), [])
    }
}
