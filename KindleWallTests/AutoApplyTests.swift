import XCTest
@testable import KindleWall

/// Covers the apply state machine and the auto-apply funnel — the two pieces that decide
/// whether a design edit reaches the desktop, how often, and what the user is told about it.
///
/// Runs against `FakeWallpaperManager`, so nothing here can touch the real desktop and the
/// assertions are about *how many* applies happen rather than what they look like.
@MainActor
final class AutoApplyTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var manager: FakeWallpaperManager!

    override func setUpWithError() throws {
        suiteName = "KindleWallTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        manager = FakeWallpaperManager()
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeViewModel(autoApply: Bool = true) -> MainViewModel {
        let storage = StorageService(defaults: defaults)
        storage.autoApplyDesignChanges = autoApply
        storage.dynamicWallpaperEnabled = false   // keep the HEIC encoder out of a timing test
        storage.syncAllSpaces = false

        let viewModel = MainViewModel(wallpaperManager: manager, storage: storage)
        let clipping = Clipping(
            bookTitle: "Doğanın Sesi",
            author: "Baba Dioum",
            text: "İnsan ancak sevdiği şeyi korur, ancak anladığı şeyi sever."
        )
        viewModel.clippings = [clipping]
        viewModel.currentClipping = clipping
        return viewModel
    }

    /// Spins the run loop until `condition` holds or the deadline passes.
    @discardableResult
    private func wait(upTo seconds: TimeInterval = 8,
                      for condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    /// Lets any pending debounce fire and settle without asserting on it.
    private func settle(_ seconds: TimeInterval = 3) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - State machine

    func test_manualApply_movesThroughApplyingToApplied() {
        let viewModel = makeViewModel()

        viewModel.applyWallpaper()
        XCTAssertTrue(viewModel.applyStatus.isApplying, "apply çağrılır çağrılmaz 'uygulanıyor' olmalı")

        XCTAssertTrue(wait { viewModel.applyStatus.isApplied }, "apply 'uygulandı' ile bitmeli")
        XCTAssertEqual(manager.applyCount, 1)
    }

    func test_failedApply_reportsFailureAndNeverPassesThroughApplied() {
        let viewModel = makeViewModel()
        manager.applyError = KindleWallError.screenNotAvailable

        var sawApplied = false
        viewModel.applyWallpaper()
        _ = wait {
            if viewModel.applyStatus.isApplied { sawApplied = true }
            if case .failed = viewModel.applyStatus { return true }
            return false
        }

        guard case .failed = viewModel.applyStatus else {
            return XCTFail("başarısız apply .failed ile bitmeli, şu an: \(viewModel.applyStatus)")
        }
        XCTAssertFalse(sawApplied, "başarısız apply hiçbir noktada 'uygulandı' görünmemeli")
    }

    /// The success-but-degraded case used to be written to `errorMessage`, so the user saw a
    /// green "Uygulandı" and a red error line at the same time.
    ///
    /// The encoder is forced to fail so the fallback is guaranteed — asserting on a degrade
    /// that only *might* happen would be coverage in name only.
    func test_degradedSuccess_isCarriedOnTheAppliedCaseNotErrorMessage() throws {
        let storage = StorageService(defaults: defaults)
        storage.dynamicWallpaperEnabled = true
        storage.syncAllSpaces = false

        let viewModel = MainViewModel(
            wallpaperManager: manager,
            storage: storage,
            heicEncoder: FailingHEICEncoder()
        )
        viewModel.currentClipping = Clipping(
            bookTitle: "Doğanın Sesi", author: "Baba Dioum",
            text: "İnsan ancak sevdiği şeyi korur, ancak anladığı şeyi sever."
        )

        viewModel.applyWallpaper()
        XCTAssertTrue(wait { viewModel.applyStatus.isApplied }, "statik yedeğe düşse de uygulanmalı")

        guard case let .applied(_, _, degraded) = viewModel.applyStatus else {
            return XCTFail("beklenen durum .applied, şu an: \(viewModel.applyStatus)")
        }
        XCTAssertNotNil(degraded, "dinamik başarısız olunca uyarı .applied üzerinde taşınmalı")
        XCTAssertNil(viewModel.errorMessage,
                     "bozulmuş başarı errorMessage'a yazılmamalı — yoksa yeşil 'Uygulandı' ile kırmızı hata yan yana çıkar")
    }

    /// Regression test for the old unstored 1.5 s reset task: two applies inside the dwell
    /// window meant the first one's timer wiped the second one's success early.
    func test_dwellOfALaterApplyIsNotEndedByAnEarlierApplysTimer() {
        let viewModel = makeViewModel()

        viewModel.applyWallpaper()
        XCTAssertTrue(wait { viewModel.applyStatus.isApplied })

        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        viewModel.applyWallpaper()
        XCTAssertTrue(wait { viewModel.applyStatus.isApplied })

        // Past the *first* apply's dwell deadline, but well inside the second's.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertTrue(viewModel.applyStatus.isApplied,
                      "önceki apply'ın zamanlayıcısı sonrakinin durumunu silmemeli")
    }

    // MARK: - Debounce

    func test_aBurstOfTypographyEdits_appliesExactlyOnce() {
        let viewModel = makeViewModel()

        for scale in stride(from: 0.8, to: 1.3, by: 0.05) {
            var t = viewModel.typography
            t.fontScale = scale
            viewModel.updateTypography(t)
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertTrue(wait { manager.applyCount >= 1 }, "yerleşme sonrası uygulanmalı")
        settle(2)
        XCTAssertEqual(manager.applyCount, 1, "sürükleme boyunca tek apply olmalı")
    }

    /// Six deliberate style clicks at browsing cadence must still coalesce into one apply —
    /// this is the case the 900 ms delay was chosen for.
    func test_browsingStylesAtClickCadence_appliesOnce() {
        let viewModel = makeViewModel()

        for style in WallpaperStyle.allCases {
            viewModel.updateStyle(style)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        XCTAssertTrue(wait { manager.applyCount >= 1 })
        settle(2)
        XCTAssertEqual(manager.applyCount, 1, "göz gezdirme tek apply'a inmeli")
    }

    /// The sharp assertion is `shownClippingIDs`: `selectRandomClipping` mutates that set, so
    /// this catches an accidental re-roll even when the same clipping happens to be re-picked.
    func test_autoApply_neverRerollsTheQuote() {
        let viewModel = makeViewModel()
        let storage = StorageService(defaults: defaults)
        let idBefore = viewModel.currentClipping?.id
        let shownBefore = storage.shownClippingIDs

        viewModel.updateStyle(.paper)
        XCTAssertTrue(wait { manager.applyCount >= 1 })

        XCTAssertEqual(viewModel.currentClipping?.id, idBefore, "otomatik uygulama alıntıyı değiştirmemeli")
        XCTAssertEqual(storage.shownClippingIDs, shownBefore, "gösterilen alıntı kümesi dokunulmamalı")
    }

    func test_autoApplyOff_leavesTheDesktopAloneAndSaysSo() {
        let viewModel = makeViewModel(autoApply: false)

        viewModel.updateStyle(.grid)
        settle(2.5)

        XCTAssertEqual(manager.applyCount, 0, "kapalıyken masaüstüne yazılmamalı")
        XCTAssertEqual(viewModel.applyStatus, .unapplied)
        XCTAssertTrue(viewModel.applyStatus.needsManualApply)
    }

    func test_manualApplyWhileAutoApplyOff_reachesTheDesktop() {
        let viewModel = makeViewModel(autoApply: false)
        viewModel.updateStyle(.grid)
        settle(1)

        viewModel.applyDesignNow()
        XCTAssertTrue(wait { manager.applyCount == 1 })
    }

    // MARK: - All-Spaces propagation

    /// Propagating restarts the wallpaper agent and reloads every Space, so an automatic apply
    /// writes the active Space now and defers propagation until editing stops.
    func test_automaticApply_defersAllSpacesPropagation() {
        let viewModel = makeViewModel()

        viewModel.updateStyle(.dawn)
        XCTAssertTrue(wait { manager.applyCount >= 1 })

        XCTAssertEqual(manager.propagations.first, false,
                       "otomatik apply anında tüm-Space yayılımı istememeli")
        XCTAssertEqual(manager.deferredSyncCount, 0, "yayılım henüz beklemede olmalı")

        XCTAssertTrue(wait(upTo: 6) { manager.deferredSyncCount == 1 },
                      "düzenleme durunca yayılım bir kez çalışmalı")
    }

    func test_manualApply_propagatesImmediately() {
        let viewModel = makeViewModel()
        viewModel.applyWallpaper(reason: .manual)
        XCTAssertTrue(wait { manager.applyCount == 1 })
        XCTAssertEqual(manager.propagations.first, true)
    }

    // MARK: - Undo

    func test_undoRestoresTheDesignFromBeforeTheBurst() {
        let viewModel = makeViewModel()
        let originalStyle = viewModel.selectedStyle

        viewModel.updateStyle(.dawn)
        viewModel.updateStyle(.depth)
        viewModel.updateStyle(.grid)
        XCTAssertTrue(wait { manager.applyCount >= 1 })

        XCTAssertNotNil(viewModel.designUndo, "otomatik uygulama geri alınabilir olmalı")
        viewModel.undoDesign()

        XCTAssertEqual(viewModel.selectedStyle, originalStyle,
                       "geri al, tek tık değil, düzenleme dizisinin başına dönmeli")
    }

    func test_schedulerApply_offersNoDesignUndo() {
        let viewModel = makeViewModel()
        viewModel.applyWallpaper(reason: .scheduler)
        XCTAssertTrue(wait { viewModel.applyStatus.isApplied })

        XCTAssertEqual(viewModel.applyStatus.reason, .scheduler)
        XCTAssertFalse(ApplyReason.scheduler.offersDesignUndo,
                       "zamanlayıcı alıntıyı değiştirir; tasarımı geri almayı önermek yanıltıcı olur")
    }
}
