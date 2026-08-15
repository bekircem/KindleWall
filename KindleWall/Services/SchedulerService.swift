import Foundation
import Combine

// MARK: - Protocol

/// Protocol for managing wallpaper change scheduling.
///
/// Main-actor isolated: the implementation drives a `Timer` on `RunLoop.main`, so every callback
/// already arrives on the main thread. Stating it lets the compiler check what was previously
/// just a convention.
@MainActor
protocol SchedulerServiceProtocol {
    /// The current schedule interval.
    var interval: ScheduleInterval { get set }

    /// The custom schedule date (used when interval is .custom).
    var customDate: Date? { get set }

    /// Whether the scheduler is currently active.
    var isActive: Bool { get }

    /// The next scheduled change date.
    var nextChangeDate: Date? { get }

    /// Starts the scheduler with the given callback.
    /// - Parameter onChange: A closure called when it's time to change the wallpaper.
    func start(onChange: @escaping @MainActor @Sendable () -> Void)

    /// Stops the scheduler.
    func stop()

    /// Pauses or resumes the scheduler.
    func togglePause()

    /// Triggers an immediate wallpaper change.
    func triggerNow()
}

// MARK: - Implementation

/// Manages timed wallpaper changes using Timer.
@MainActor
final class SchedulerService: SchedulerServiceProtocol {
    var interval: ScheduleInterval {
        didSet { reschedule() }
    }

    var customDate: Date?

    private(set) var isActive: Bool = false
    private(set) var nextChangeDate: Date?

    /// `nonisolated(unsafe)` so `deinit` can reach it — see the note there.
    nonisolated(unsafe) private var timer: Timer?
    private var onChange: (@MainActor @Sendable () -> Void)?
    private var isPaused: Bool = false

    init(interval: ScheduleInterval = .hourly) {
        self.interval = interval
    }

    func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
        self.isPaused = false
        reschedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        nextChangeDate = nil
    }

    func togglePause() {
        if isPaused {
            isPaused = false
            reschedule()
        } else {
            isPaused = true
            timer?.invalidate()
            timer = nil
            isActive = false
        }
    }

    func triggerNow() {
        onChange?()
        reschedule()
    }

    // MARK: - Private

    private func reschedule() {
        timer?.invalidate()
        timer = nil

        guard !isPaused, let onChange = onChange else {
            isActive = false
            return
        }

        guard let timeInterval = interval.timeInterval else {
            // Custom: schedule for a specific time
            scheduleCustom(onChange: onChange)
            return
        }

        nextChangeDate = Date().addingTimeInterval(timeInterval)
        isActive = true

        timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { [weak self] _ in
            // Added to RunLoop.main below, so this body is on the main thread already.
            MainActor.assumeIsolated {
                onChange()
                self?.nextChangeDate = Date().addingTimeInterval(timeInterval)
            }
        }
        // Ensure the timer fires even when the app is in the background
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func scheduleCustom(onChange: @escaping @MainActor @Sendable () -> Void) {
        guard let customDate = customDate else {
            isActive = false
            return
        }

        let now = Date()
        var target = customDate
        // If the target time has passed today, schedule for tomorrow
        while target <= now {
            target = Calendar.current.date(byAdding: .day, value: 1, to: target) ?? target.addingTimeInterval(86400)
        }

        let delay = target.timeIntervalSince(now)
        nextChangeDate = target
        isActive = true

        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                onChange()
                // Reschedule for next day
                self?.scheduleCustom(onChange: onChange)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    deinit {
        // Not `stop()`: deinit is not actor-isolated. Invalidation still has to happen here.
        // A timer that is never invalidated stays retained by the run loop and keeps firing,
        // and its closure holds `onChange` strongly — so a discarded scheduler would go on
        // changing the wallpaper for the rest of the process. That is harmless with one
        // scheduler per app, and is exactly how a test suite ends up fighting for the desktop.
        //
        // Deinit of a main-actor object released on the main actor runs there too, which is the
        // run loop that installed the timer.
        timer?.invalidate()
    }
}
