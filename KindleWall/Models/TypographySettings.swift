import Foundation

/// User-adjustable typography settings for wallpaper rendering.
struct TypographySettings: Codable, Equatable {

    /// Which decorative element to draw above the quote text.
    enum DecorationStyle: String, Codable, CaseIterable, Identifiable {
        var id: String { rawValue }
        case classicQuote   // Large " typographic open-quote mark (default)
        case minimalDots    // Original dots + bars design
        case line           // Simple thin horizontal rule
        case none           // No decoration
    }

    /// Font family used for the quote text.
    enum FontFamily: String, Codable, CaseIterable, Identifiable {
        var id: String { rawValue }
        case serif      // New York — literary, warm
        case sansSerif  // SF Pro — clean, modern
        case classic    // Palatino — elegant, high-contrast humanist serif
        case monospace  // SF Mono — technical, precise

        var displayName: String {
            switch self {
            case .serif:     return "Serif"
            case .sansSerif: return "Sans"
            case .classic:   return "Klasik"
            case .monospace: return "Mono"
            }
        }
    }

    // MARK: - Basic settings

    /// Font size multiplier (0.6 = small, 1.0 = default, 1.4 = large).
    var fontScale: Double = 1.0

    /// Vertical position bias: -1.0 = top, 0.0 = center, 1.0 = bottom.
    var verticalPosition: Double = 0.0

    /// Horizontal padding multiplier (0.5 = narrow margins, 1.0 = default, 1.5 = wide margins).
    var paddingScale: Double = 1.0

    /// Line spacing multiplier (0.8 = tight, 1.0 = default, 1.3 = loose).
    var lineSpacingScale: Double = 1.0

    /// Decorative element rendered above the quote text.
    var decorativeStyle: DecorationStyle = .classicQuote

    /// Custom background gradient start color as hex string (e.g. "FF6B35"). nil = use style default.
    var backgroundStartColorHex: String? = nil

    /// Custom background gradient end color as hex string. nil = use style default.
    var backgroundEndColorHex: String? = nil

    // MARK: - Advanced settings

    /// Font family for the quote text.
    var fontFamily: FontFamily = .serif

    /// Whether to draw a drop shadow behind the quote text.
    var shadowEnabled: Bool = false

    /// Shadow blur radius in points (1–20). Only used when shadowEnabled is true.
    var shadowRadius: Double = 4.0

    /// Additional letter spacing in points. 0 = default, positive = wider, negative = tighter.
    var letterSpacing: Double = 0.0

    /// Quote text opacity (0.3–1.0). Lower values create a translucent/ghosted effect.
    var textOpacity: Double = 1.0

    static let `default` = TypographySettings()
}
