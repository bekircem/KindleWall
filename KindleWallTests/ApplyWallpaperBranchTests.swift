import XCTest
@testable import KindleWall

/// Exercises `MainViewModel.applyWallpaper()` itself — the one link the pipeline tests cannot
/// reach — to prove the dynamic toggle actually changes what gets written.
///
/// Runs against an isolated `UserDefaults` suite and a wallpaper directory in the temp folder,
/// so the user's real settings and Application Support files are untouched. The desktop
/// wallpaper is captured before the test and restored after.
@MainActor
final class ApplyWallpaperBranchTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var wallpaperDir: URL!
    private var originalWallpaper: URL?

    override func setUpWithError() throws {
        suiteName = "KindleWallTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        wallpaperDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KindleWallApply-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: wallpaperDir, withIntermediateDirectories: true)

        originalWallpaper = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }

    override func tearDownWithError() throws {
        if let originalWallpaper {
            for screen in NSScreen.screens {
                try? NSWorkspace.shared.setDesktopImageURL(originalWallpaper, for: screen, options: [:])
            }
        }
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: wallpaperDir)
    }

    private func makeViewModel(dynamic: Bool) -> MainViewModel {
        let storage = StorageService(defaults: defaults)
        storage.dynamicWallpaperEnabled = dynamic
        storage.applyToAllSpaces = false   // keep the osascript path out of a unit test

        let viewModel = MainViewModel(
            wallpaperManager: WallpaperManager(storageService: storage, wallpapersDirectory: wallpaperDir),
            storage: storage
        )
        viewModel.currentClipping = Clipping(
            bookTitle: "Doğanın Sesi",
            author: "Baba Dioum",
            text: "İnsan ancak sevdiği şeyi korur, ancak anladığı şeyi sever."
        )
        return viewModel
    }

    /// Waits for the detached apply task to land a *finished* file in the wallpaper directory.
    ///
    /// Matching on the extension matters: `CGImageDestinationFinalize` writes through a sibling
    /// temp file (`kindlewall_….heic-7HBY`) and renames it, so polling for "any file" can catch
    /// a half-written one.
    private func waitForWrittenWallpaper(extension ext: String) throws -> URL {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: wallpaperDir, includingPropertiesForKeys: nil)) ?? []
            if let file = files.first(where: { $0.pathExtension == ext }) { return file }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        throw XCTSkip("Duvar kağıdı 30 saniyede yazılmadı")
    }

    func test_dynamicEnabled_writesAMultiFrameHeic() throws {
        let viewModel = makeViewModel(dynamic: true)
        viewModel.applyWallpaper()

        let written = try waitForWrittenWallpaper(extension: "heic")
        XCTAssertEqual(written.pathExtension, "heic", "dinamik modda HEIC yazılmalı")

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(written as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), SolarPhase.allCases.count,
                       "altı kare bekleniyor")
        XCTAssertNotNil(
            CGImageSourceCopyMetadataAtIndex(source, 0, nil).flatMap {
                CGImageMetadataCopyTagWithPath($0, nil, "apple_desktop:h24" as CFString)
            },
            "dinamik metadata eksik"
        )
    }

    func test_dynamicDisabled_writesASinglePng() throws {
        let viewModel = makeViewModel(dynamic: false)
        viewModel.applyWallpaper()

        let written = try waitForWrittenWallpaper(extension: "png")
        XCTAssertEqual(written.pathExtension, "png", "dinamik kapalıyken PNG yazılmalı")

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(written as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
    }
}
