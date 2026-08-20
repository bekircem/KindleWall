import Foundation

/// Defines how frequently the wallpaper should automatically change.
enum ScheduleInterval: String, Codable, CaseIterable, Identifiable {
    case every30Minutes = "30 Dakikada Bir"
    case hourly = "Saatlik"
    case every3Hours = "3 Saatte Bir"
    case every6Hours = "6 Saatte Bir"
    case daily = "Günlük"
    case custom = "Özel"

    var id: String { rawValue }

    /// Short label for the segmented picker.
    ///
    /// Separate from `rawValue` on purpose: the raw value is what `StorageService` writes to
    /// UserDefaults, so renaming a case there would silently drop every existing user back to
    /// the `hourly` fallback. Six segments of "30 Dakikada Bir" length crush each other at the
    /// window's minimum width; these do not.
    var displayName: String {
        switch self {
        case .every30Minutes: return String(localized: "30 min")
        case .hourly:         return String(localized: "1 hour")
        case .every3Hours:    return String(localized: "3 hours")
        case .every6Hours:    return String(localized: "6 hours")
        case .daily:          return String(localized: "Daily")
        case .custom:         return String(localized: "Custom")
        }
    }

    /// Returns the interval in seconds, or nil for custom schedules.
    var timeInterval: TimeInterval? {
        switch self {
        case .every30Minutes: return 30 * 60
        case .hourly: return 60 * 60
        case .every3Hours: return 3 * 60 * 60
        case .every6Hours: return 6 * 60 * 60
        case .daily: return 24 * 60 * 60
        case .custom: return nil
        }
    }
}
