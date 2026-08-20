import XCTest
@testable import KindleWall

/// The app persisted only clipping *IDs*, never their contents, and read the originals through a
/// security-scoped bookmark pointing at the Kindle itself. With the device unplugged the
/// bookmark could not resolve, so the app started with zero clippings: nothing to display,
/// nothing to render a wallpaper from, and an error where the quote should be. These tests pin
/// the local copy that fixes it.
@MainActor
final class ClippingsCacheTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sourceFile: URL!

    /// Stands in for the Kindle's file. Deleting it simulates unplugging the device.
    private func writeSourceFile() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KindleWallSource-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("My Clippings.txt")

        let contents = """
        Atomic Habits (James Clear)
        - Your Highlight on page 23 | location 340-342 | Added on Monday, January 15, 2024 10:30:22 AM

        Every action you take is a vote for the type of person you wish to become.
        ==========
        Meditations (Marcus Aurelius)
        - Your Highlight on page 42 | location 633-635 | Added on Tuesday, February 20, 2024 09:15:33 AM

        You have power over your mind - not outside events.
        ==========
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    override func setUp() async throws {
        suiteName = TestDefaults.makeSuiteName("cache")
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        sourceFile = try writeSourceFile()
        try? FileManager.default.removeItem(at: Constants.Paths.localClippingsFile)
    }

    override func tearDown() async throws {
        TestDefaults.destroy(suiteNamed: suiteName, defaults: defaults)
        try? FileManager.default.removeItem(at: sourceFile.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: Constants.Paths.localClippingsFile)
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    func test_successfulImportCachesTheFileLocally() throws {
        let storage = StorageService(defaults: defaults)
        let viewModel = MainViewModel(storage: storage)

        viewModel.importClippings(from: sourceFile)

        XCTAssertTrue(waitUntil { !viewModel.clippings.isEmpty }, "import tamamlanmadı")
        XCTAssertTrue(waitUntil { storage.localClippingsFileURL() != nil },
                      "başarılı import'tan sonra yerel kopya oluşmalı")
    }

    /// The scenario that made the app useless: the Kindle is gone on the next launch.
    func test_afterTheSourceDisappears_clippingsStillLoadFromTheLocalCopy() throws {
        let storage = StorageService(defaults: defaults)

        let first = MainViewModel(storage: storage)
        first.importClippings(from: sourceFile)
        XCTAssertTrue(waitUntil { !first.clippings.isEmpty }, "ilk import tamamlanmadı")
        XCTAssertTrue(waitUntil { storage.localClippingsFileURL() != nil }, "yerel kopya oluşmadı")

        // Unplug: the original file and its whole volume are gone.
        try FileManager.default.removeItem(at: sourceFile.deletingLastPathComponent())
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))

        // A fresh launch, resolving from storage rather than a passed-in URL.
        let second = MainViewModel(storage: storage)
        second.loadClippings()

        XCTAssertTrue(waitUntil { !second.clippings.isEmpty },
                      "Kindle çıkarılmışken yerel kopyadan alıntılar yüklenmeli")
        XCTAssertNil(second.errorMessage,
                     "yerel kopya varken hata gösterilmemeli: \(second.errorMessage ?? "")")
    }

    func test_withNoSourceAndNoCache_theUserIsAskedToPickAFile() {
        let storage = StorageService(defaults: defaults)
        let viewModel = MainViewModel(storage: storage)

        viewModel.loadClippings()

        XCTAssertEqual(viewModel.errorMessage,
                       String(localized: "Please choose your My Clippings.txt file."))
    }

    func test_cachingIgnoresACopyOntoItself() throws {
        let storage = StorageService(defaults: defaults)
        try Data("veri".utf8).write(to: Constants.Paths.localClippingsFile)

        storage.cacheClippingsFile(from: Constants.Paths.localClippingsFile)

        XCTAssertEqual(try Data(contentsOf: Constants.Paths.localClippingsFile),
                       Data("veri".utf8), "kendi üstüne kopyalama dosyayı bozmamalı")
    }
}
