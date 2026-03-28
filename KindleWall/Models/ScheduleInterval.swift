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
