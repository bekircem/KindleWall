import Foundation

/// User-adjustable typography settings for wallpaper rendering.
struct TypographySettings: Codable, Equatable {

    /// Which decorative element to draw above the quote text.
    enum DecorationStyle: String, Codable, CaseIterable {
        case classicQuote   // Large " typographic open-quote mark (default)
        case minimalDots    // Original dots + bars design
        case line           // Simple thin horizontal rule
        case none           // No decoration
    }

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

    static let `default` = TypographySettings()
}
