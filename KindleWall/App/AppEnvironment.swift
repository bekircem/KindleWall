import Foundation

/// Shared app-level container that gives AppDelegate and GlobalHotkeyManager
/// a weak reference to MainViewModel without creating an import cycle.
///
/// Main-actor isolated because the thing it hands out is: reaching `MainViewModel` from
/// anywhere else was never safe, it just was not checked.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()
    weak var mainViewModel: MainViewModel?
    private init() {}
}
