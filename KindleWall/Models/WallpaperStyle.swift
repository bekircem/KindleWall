import Foundation

/// Available wallpaper visual styles for rendering clippings.
///
/// The set was consolidated from eight styles to six. Three of the originals (Minimal Dark
/// `#1A1A1A`, Elegant Serif `#2C2C2C`, Modern Sans `#0D1117`) were all flat dark grey and
/// indistinguishable in use, and the style descriptions promised typography the renderer never
/// applied — the font came from the user's typography settings regardless of style. Each
/// surviving style now differs on four axes (surface, value, temperature, typographic
/// character) and carries its own default font and decoration, so picking a style is a visible
/// change. Legacy raw values still decode; see `init(persistedRawValue:)`.
enum WallpaperStyle: String, Codable, CaseIterable, Identifiable {
    case night = "Night"
    case paper = "Paper"
    case grid = "Grid"
    case dawn = "Dawn"
    case depth = "Depth"
    case forestLight = "Forest Light"

    var id: String { rawValue }

    /// Display name for the UI (Turkish).
    var displayName: String {
        switch self {
        case .night:       return String(localized: "Night")
        case .paper:       return String(localized: "Paper")
        case .grid:        return String(localized: "Grid")
        case .dawn:        return String(localized: "Dawn")
        case .depth:       return String(localized: "Depth")
        case .forestLight: return String(localized: "Forest Light")
        }
    }

    /// Brief description for the style picker.
    var styleDescription: String {
        switch self {
        case .night:       return String(localized: "Flat deep dark, serif, a classic quote mark")
        case .paper:       return String(localized: "Grainy cream, Palatino, the feel of a printed page")
        case .grid:        return String(localized: "Blue-black, monospace, fine rules")
        case .dawn:        return String(localized: "Warm gradient, sans-serif, minimal dots")
        case .depth:       return String(localized: "Cool indigo-violet gradient, sans-serif")
        case .forestLight: return String(localized: "Radial forest beam, serif")
        }
    }

    /// Typography this style applies when selected. The user can still override everything
    /// afterwards on the Tipografi page — this is the style's starting character, not a lock.
    var defaultFontFamily: TypographySettings.FontFamily {
        switch self {
        case .night:       return .serif
        case .paper:       return .classic
        case .grid:        return .monospace
        case .dawn:        return .sansSerif
        case .depth:       return .sansSerif
        case .forestLight: return .serif
        }
    }

    /// Decoration this style applies when selected. Same override rules as `defaultFontFamily`.
    var defaultDecoration: TypographySettings.DecorationStyle {
        switch self {
        case .night:       return .classicQuote
        case .paper:       return .classicQuote
        case .grid:        return .line
        case .dawn:        return .minimalDots
        case .depth:       return .line
        case .forestLight: return .line
        }
    }

    /// Whether the style's background is light — drives text colour and the solar night flip.
    var hasLightBackground: Bool {
        self == .paper
    }

    // MARK: - Migration

    /// Raw values written by versions that shipped the eight-style set, mapped to their successor.
    private static let legacyMigrations: [String: WallpaperStyle] = [
        "Minimal Dark":     .night,
        "Elegant Serif":    .night,
        "Minimal Light":    .paper,
        "Paper Texture":    .paper,
        "Modern Sans":      .grid,
        "Gradient Warm":    .dawn,
        "Gradient Cool":    .depth,
        // Nature Blur was a green gradient. Forest Light keeps the green identity rather than
        // dropping these users onto the unrelated indigo of Depth.
        "Nature Blur":      .forestLight
    ]

    /// Decodes a stored raw value, translating retired style names to their successor.
    /// - Parameter persistedRawValue: A raw value read from UserDefaults or CloudKit.
    /// - Returns: The matching style, or nil if the value belongs to neither set.
    init?(persistedRawValue: String) {
        if let current = WallpaperStyle(rawValue: persistedRawValue) {
            self = current
        } else if let migrated = Self.legacyMigrations[persistedRawValue] {
            self = migrated
        } else {
            return nil
        }
    }
}
