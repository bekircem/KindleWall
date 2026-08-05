import XCTest
@testable import KindleWall

/// Drives `MainViewModel` the way a user clicking around does: switching styles quickly,
/// applying, and letting previews overlap. Reproduction harness for the reported freezes and
/// the EXC_BAD_ACCESS crash.
@MainActor
final class InteractionStressTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var wallpaperDir: URL!
    private var originalWallpaper: URL?

    override func setUpWithError() throws {
        suiteName = "KindleWallStress-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        wallpaperDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KindleWallStress-\(UUID().uuidString)")
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
        storage.applyToAllSpaces = false

        let viewModel = MainViewModel(
            wallpaperManager: WallpaperManager(storageService: storage, wallpapersDirectory: wallpaperDir),
            storage: storage
        )
        viewModel.clippings = (0..<20).map {
            Clipping(bookTitle: "Kitap \($0)", author: "Yazar \($0)",
                     text: "İnsan ancak sevdiği şeyi korur, ancak anladığı şeyi sever. \($0)")
        }
        viewModel.currentClipping = viewModel.clippings.first
        return viewModel
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Rapid style switching: every change writes typography, regenerates a preview and, in the
    /// app, can trigger an apply. Previous renders are cancelled mid-flight.
    func test_rapidStyleSwitchingWhileApplying() {
        let viewModel = makeViewModel(dynamic: true)

        for round in 0..<12 {
            let style = WallpaperStyle.allCases[round % WallpaperStyle.allCases.count]
            viewModel.updateStyle(style)
            viewModel.applyWallpaper()
            spin(0.05)   // let the detached tasks get going before superseding them
        }

        spin(6)
        XCTAssertFalse(viewModel.isApplying, "uygulama takılı kaldı")
    }

    /// The exact call `selectAndApply` makes — preview and apply started back to back —
    /// repeated while earlier rounds are still running.
    func test_selectAndApplyStorm() {
        let viewModel = makeViewModel(dynamic: true)

        for clipping in viewModel.clippings.prefix(10) {
            viewModel.selectAndApply(clipping)
            spin(0.05)
        }

        spin(6)
        XCTAssertFalse(viewModel.isApplying, "uygulama takılı kaldı")
    }

    /// Measures how long the main thread is blocked by a single apply. The whole point of the
    /// detached pipeline is that this stays near zero.
    func test_applyDoesNotBlockTheMainThread() {
        let viewModel = makeViewModel(dynamic: true)

        let start = CFAbsoluteTimeGetCurrent()
        viewModel.applyWallpaper()
        let blocked = CFAbsoluteTimeGetCurrent() - start

        spin(6)
        XCTAssertLessThan(blocked, 0.05,
                          "applyWallpaper ana thread'i \(Int(blocked * 1000)) ms bloke etti")
    }

    /// The settings row that shows today's phase times builds its data in a stored property,
    /// so it is recomputed every time SwiftUI recreates the view. Measures that cost.
    func test_solarScheduleLookupCost() {
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<50 {
            _ = SunCalculator().phases(for: Date(), at: GeoCoordinate.fromSystemTimeZone())
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let perCall = elapsed / 50 * 1000

        print("SOLAR LOOKUP: \(String(format: "%.2f", perCall)) ms/çağrı")
        XCTAssertLessThan(perCall, 1.0,
                          "faz araması çağrı başına \(String(format: "%.2f", perCall)) ms — SwiftUI her gövde değerlendirmesinde bunu ödüyor")
    }
}
