import Foundation

/// Shared app-level container that gives AppDelegate and GlobalHotkeyManager
/// a weak reference to MainViewModel without creating an import cycle.
final class AppEnvironment {
    static let shared = AppEnvironment()
    weak var mainViewModel: MainViewModel?
    private init() {}
}
