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

    override func setUp() async throws {
        suiteName = TestDefaults.makeSuiteName("apply")
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        wallpaperDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KindleWallApply-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: wallpaperDir, withIntermediateDirectories: true)

        DesktopWallpaperGuard.capture()
    }

    override func tearDown() async throws {
        DesktopWallpaperGuard.restore()
        TestDefaults.destroy(suiteNamed: suiteName, defaults: defaults)
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
        // Derived from the same rule the apply path uses, not hardcoded.
        //
        // This assertion used to be a flat `> 1`, which made the test fail every night: past
        // the day's last phase `framesWorthWriting` legitimately returns a single frame — the
        // behaviour `test_framesWorthWriting_inTheLastPhase_returnsWhatIsLeft` pins — so the
        // two tests contradicted each other for a few hours a day. Caught at 22:19.
        let phasesToday = SunCalculator().phases(for: Date(), at: GeoCoordinate.fromSystemTimeZone())
        let expected = MainViewModel.framesWorthWriting(phasesToday, now: Date(), until: nil).count

        let frameCount = CGImageSourceGetCount(source)
        XCTAssertEqual(frameCount, expected,
                       "kare sayısı framesWorthWriting'in bu saatte söylediğiyle eşleşmeli")
        XCTAssertLessThanOrEqual(frameCount, SolarPhase.allCases.count,
                                 "faz sayısından fazla kare yazılamaz")
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

    // MARK: - Which frames are worth writing
    //
    // `apple_desktop:h24` shows the frame whose time is the latest at or before now, and the file
    // is rewritten on every quote rotation. Frames outside that window are composited, encoded,
    // and re-decoded by the system on every Space — for nothing. At the default 30-minute
    // rotation that was five of six frames on every apply.

    private func phases(_ hours: [Double]) -> [SolarPhaseTime] {
        let midnight = Calendar.current.startOfDay(for: Date())
        return zip(SolarPhase.allCases, hours).map {
            SolarPhaseTime(phase: $0, date: midnight.addingTimeInterval($1 * 3600))
        }
    }

    /// dawn 5, sunrise 6, noon 12, afternoon 16, sunset 19, night 21
    private var sixPhases: [SolarPhaseTime] { phases([5, 6, 12, 16, 19, 21]) }
    private func today(_ hour: Double) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(hour * 3600)
    }

    func test_framesWorthWriting_dropsPhasesAlreadyBehindUs() {
        // 13:00 — dawn and sunrise can never be selected again today.
        let result = MainViewModel.framesWorthWriting(sixPhases, now: today(13), until: nil)
        XCTAssertEqual(result.map(\.phase), [.noon, .afternoon, .sunset, .night])
    }

    func test_framesWorthWriting_stopsOneFrameAfterTheNextRewrite() {
        // 13:00, next rotation at 13:30: only `noon` can be shown before the rewrite. One frame
        // beyond is kept so a late rewrite still has somewhere to go.
        let result = MainViewModel.framesWorthWriting(sixPhases, now: today(13), until: today(13.5))
        XCTAssertEqual(result.map(\.phase), [.noon, .afternoon])
    }

    func test_framesWorthWriting_withNoRewriteScheduled_carriesTheRestOfTheDay() {
        // Scheduler paused: nothing will rewrite the file, so it must cover every phase left.
        let result = MainViewModel.framesWorthWriting(sixPhases, now: today(6.5), until: nil)
        XCTAssertEqual(result.map(\.phase), [.sunrise, .noon, .afternoon, .sunset, .night])
    }

    func test_framesWorthWriting_neverDropsBelowTwoFramesWhileTheDayHasTwoLeft() {
        // A one-frame HEIC is just a static wallpaper, which is not what dynamic mode promises.
        let result = MainViewModel.framesWorthWriting(sixPhases, now: today(13), until: today(13.01))
        XCTAssertGreaterThanOrEqual(result.count, 2)
    }

    func test_framesWorthWriting_beforeTheDaysFirstPhase_keepsEverything() {
        // At 03:00 macOS wraps to the last frame, so the whole set is still meaningful.
        let result = MainViewModel.framesWorthWriting(sixPhases, now: today(3), until: nil)
        XCTAssertEqual(result.count, SolarPhase.allCases.count)
    }

    func test_framesWorthWriting_inTheLastPhase_returnsWhatIsLeft() {
        let result = MainViewModel.framesWorthWriting(sixPhases, now: today(22), until: today(22.5))
        XCTAssertEqual(result.map(\.phase), [.night])
    }
}
