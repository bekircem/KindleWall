import Foundation

/// The six moments a dynamic wallpaper is rendered for.
///
/// Six rather than sixteen: macOS cross-fades between frames, and the colour curve is smooth,
/// so extra frames buy no visible detail while multiplying file size. The golden hours get
/// their own frames because that is where the change is worth seeing.
enum SolarPhase: String, CaseIterable, Identifiable {
    case dawn        // civil twilight, before the sun clears the horizon
    case sunrise     // golden hour
    case noon        // solar noon
    case afternoon
    case sunset      // golden hour
    case night

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dawn:      return String(localized: "Dawn")
        case .sunrise:   return String(localized: "Sunrise")
        case .noon:      return String(localized: "Noon")
        case .afternoon: return String(localized: "Afternoon")
        case .sunset:    return String(localized: "Sunset")
        case .night:     return String(localized: "Night")
        }
    }
}

/// A phase pinned to a wall-clock time on a specific day.
struct SolarPhaseTime: Equatable {
    let phase: SolarPhase
    let date: Date

    /// Position within the day, 0.0 at midnight to 1.0 at the next midnight — the unit
    /// `apple_desktop:h24` metadata expects.
    func dayFraction(calendar: Calendar = .current) -> Double {
        let startOfDay = calendar.startOfDay(for: date)
        let seconds = date.timeIntervalSince(startOfDay)
        return min(max(seconds / 86_400, 0), 0.999_9)
    }
}
