import XCTest
@testable import KindleWall

/// The scheduler is the reason the app exists — everything else decorates a wallpaper that this
/// class decides to change. It had no tests. These cover the state it publishes and the two
/// pieces of arithmetic a user would notice getting wrong: when the next change lands, and
/// whether a custom time that has already passed today waits for tomorrow.
///
/// No test waits for a real timer to fire. Timers here are asserted through the state the
/// scheduler exposes, so the suite stays fast and cannot flake on scheduling jitter.
@MainActor
final class SchedulerServiceTests: XCTestCase {

    // MARK: - Interval schedules

    func test_start_marksItselfActiveAndAnnouncesTheNextChange() {
        let scheduler = SchedulerService(interval: .hourly)
        scheduler.start {}

        XCTAssertTrue(scheduler.isActive)
        let next = try? XCTUnwrap(scheduler.nextChangeDate)
        XCTAssertEqual(next?.timeIntervalSinceNow ?? 0, 3600, accuracy: 5)
    }

    func test_stop_clearsBothTheFlagAndTheAnnouncedDate() {
        let scheduler = SchedulerService(interval: .hourly)
        scheduler.start {}
        scheduler.stop()

        XCTAssertFalse(scheduler.isActive)
        XCTAssertNil(scheduler.nextChangeDate, "duraklatılmış bir zamanlayıcı sonraki saati göstermemeli")
    }

    func test_changingTheIntervalReschedulesRatherThanKeepingTheOldOne() {
        let scheduler = SchedulerService(interval: .daily)
        scheduler.start {}
        XCTAssertEqual(scheduler.nextChangeDate?.timeIntervalSinceNow ?? 0, 86_400, accuracy: 5)

        scheduler.interval = .every30Minutes

        XCTAssertEqual(scheduler.nextChangeDate?.timeIntervalSinceNow ?? 0, 1800, accuracy: 5,
                       "aralık değişince sonraki değişim yeni aralığa göre hesaplanmalı")
    }

    // MARK: - Pause

    func test_pause_stopsTheScheduleAndResumeBringsItBack() {
        let scheduler = SchedulerService(interval: .hourly)
        scheduler.start {}

        scheduler.togglePause()
        XCTAssertFalse(scheduler.isActive, "duraklatılmışken aktif görünmemeli")

        scheduler.togglePause()
        XCTAssertTrue(scheduler.isActive)
        XCTAssertEqual(scheduler.nextChangeDate?.timeIntervalSinceNow ?? 0, 3600, accuracy: 5,
                       "devam ettirmek sayacı baştan başlatmalı")
    }

    func test_triggerNow_firesTheCallbackAndRestartsTheCountdown() {
        let scheduler = SchedulerService(interval: .hourly)
        var fired = 0
        scheduler.start { fired += 1 }

        // Move the announced date into the past so a genuine reschedule is observable.
        let before = scheduler.nextChangeDate
        scheduler.triggerNow()

        XCTAssertEqual(fired, 1, "elle tetikleme geri çağrıyı bir kez çalıştırmalı")
        XCTAssertNotNil(scheduler.nextChangeDate)
        XCTAssertGreaterThanOrEqual(scheduler.nextChangeDate ?? .distantPast,
                                    before ?? .distantPast,
                                    "tetikleme sonrası sayaç ileri gitmeli, geri değil")
    }

    func test_triggerNowWhilePaused_stillChangesTheWallpaperButStaysPaused() {
        let scheduler = SchedulerService(interval: .hourly)
        var fired = 0
        scheduler.start { fired += 1 }
        scheduler.togglePause()

        scheduler.triggerNow()

        XCTAssertEqual(fired, 1, "duraklatma, kullanıcının elle istediği değişimi engellememeli")
        XCTAssertFalse(scheduler.isActive, "elle tetikleme duraklatmayı kendiliğinden kaldırmamalı")
    }

    // MARK: - Custom clock time

    func test_customTimeAlreadyPassedToday_waitsForTomorrow() {
        let scheduler = SchedulerService(interval: .custom)
        scheduler.customDate = Date().addingTimeInterval(-3600)   // an hour ago
        scheduler.start {}

        let next = scheduler.nextChangeDate ?? .distantPast
        XCTAssertGreaterThan(next, Date(), "geçmiş bir saat asla geçmişe planlanmamalı")
        XCTAssertEqual(next.timeIntervalSinceNow, 23 * 3600, accuracy: 120,
                       "bugünü kaçırmış bir özel saat yarınki aynı saate kaymalı")
    }

    func test_customTimeStillAheadToday_keepsItToday() {
        let scheduler = SchedulerService(interval: .custom)
        scheduler.customDate = Date().addingTimeInterval(3600)    // in an hour
        scheduler.start {}

        XCTAssertEqual(scheduler.nextChangeDate?.timeIntervalSinceNow ?? 0, 3600, accuracy: 120)
    }

    func test_customIntervalWithNoDateChosen_staysInactiveRatherThanGuessing() {
        let scheduler = SchedulerService(interval: .custom)
        scheduler.customDate = nil
        scheduler.start {}

        XCTAssertFalse(scheduler.isActive)
        XCTAssertNil(scheduler.nextChangeDate)
    }

    // MARK: - Lifetime

    func test_aDiscardedScheduler_stopsChangingTheWallpaper() {
        // An un-invalidated Timer stays retained by the run loop and its closure holds `onChange`
        // strongly, so a scheduler nobody references could go on firing for the life of the
        // process. One scheduler per app makes that invisible; a test suite makes it a fight over
        // the desktop. The deinit is the guard, and this pins it.
        // A half-hourly timer would not fire during this test whether it was invalidated or not,
        // so the schedule has to be one that *would* fire — otherwise the test passes by saying
        // nothing. A custom date a fraction of a second out gives a real deadline to survive.
        var fired = 0
        autoreleasepool {
            let scheduler = SchedulerService(interval: .custom)
            scheduler.customDate = Date().addingTimeInterval(0.3)
            scheduler.start { fired += 1 }
            XCTAssertTrue(scheduler.isActive, "önce gerçekten planlanmış olmalı")
        }

        // Well past the deadline, plus its tolerance.
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        XCTAssertEqual(fired, 0, "atılmış zamanlayıcı hiçbir şey tetiklememeli")
    }
}
