import Foundation
import Sparkle

/// Owns the Sparkle updater for the app's lifetime.
///
/// Two constraints shape this type.
///
/// `SPUStandardUpdaterController` drives AppKit windows and is not `Sendable`, so under the
/// Swift 6 language mode the wrapper is pinned to the main actor and never escapes into a
/// detached task — the mirror image of the rule the render path follows.
///
/// And the controller must be *kept*. Sparkle's scheduled check belongs to the controller; one
/// created locally and allowed to go out of scope takes the check with it and the app silently
/// stops looking for updates. That is the same shape as the `SchedulerService` `Timer` bug this
/// codebase has already shipped once, so the instance is held by a singleton rather than by
/// whichever view happened to ask first.
@MainActor
final class UpdaterManager {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// False while a check is already in flight. The menu item and the button bind to this so
    /// they grey out instead of stacking sheets.
    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// User-initiated check. Always shows UI, including "you are up to date" — which is the
    /// point of a manual check.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
