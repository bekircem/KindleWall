import SwiftUI

/// Centralized design tokens for the KindleWall UI refresh.
///
/// Single source of truth for spacing, corner radii, palette, and motion — so the
/// whole app shares one visual rhythm instead of ad-hoc inline values. The signature
/// accent lives in `Assets → AccentColor`; change it there to retheme every control.
enum Theme {
    /// Consistent spacing scale (4-pt based).
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Corner radii. `card` matches the grouped container; `tile` the small icon tiles.
    enum Radius {
        static let tile: CGFloat = 7
        static let control: CGFloat = 8
        static let card: CGFloat = 14
        static let hero: CGFloat = 18
    }

    /// Dark-first palette. Content surfaces are subtle elevated fills (legibility);
    /// Liquid Glass is reserved for chrome (sidebar, toolbar, floating controls).
    enum Palette {
        /// Signature accent — driven by the asset catalog so it tints all controls.
        /// Adopted app-wide via `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`; without
        /// that build setting this resolves to the system blue no matter what the asset says.
        static let accent = Color.accentColor
        /// Label color to place *on top of* the accent fill.
        ///
        /// The accent is a light warm amber: white text over it measures 1.9:1, far under the
        /// 4.5:1 floor, while black measures 11:1. Anything that fills a surface with the
        /// accent must label it with this, not `.white`.
        static let onAccent = Color.black.opacity(0.85)
        /// Subtle elevated surface for cards on the dark canvas.
        static let cardFill = Color.white.opacity(0.05)
        /// Hairline border around cards.
        static let cardStroke = Color.white.opacity(0.09)
        /// Inset divider between rows inside a card.
        static let rowDivider = Color.white.opacity(0.06)
        /// Hover highlight for interactive rows / cards.
        static let hover = Color.white.opacity(0.07)
        /// Backdrop for an editor canvas — a recessed surface the artwork sits on, so the
        /// wallpaper reads as the subject rather than as one more panel.
        static let canvas = Color.black.opacity(0.16)
        /// Neutral icon-tile fill for chrome destinations.
        ///
        /// `systemGray` itself is too light to carry a white glyph in dark appearance —
        /// it measures 2.9:1, just under the 3:1 floor — and a mid-gray tile does not read
        /// as receding anyway. Derived from the system color rather than hardcoded, so it
        /// still follows the appearance.
        static let neutralTile = Color(nsColor: .systemGray).mix(with: .black, by: 0.35)
    }

    /// Shared animation presets so transitions feel coherent across screens.
    /// `snappy` for selections/toggles, `smooth` for content/layout changes,
    /// `hover` for lightweight pointer feedback.
    enum Motion {
        static let snappy: Animation = .snappy(duration: 0.28)
        static let smooth: Animation = .smooth(duration: 0.32)
        static let hover: Animation = .easeOut(duration: 0.15)
    }

    /// Type roles that carry the app's identity.
    ///
    /// The wallpapers this app renders are set in serif; the chrome around them was entirely
    /// SF Pro, so nothing tied the two together. Group headings now borrow the same serif —
    /// `design: .serif` resolves to New York, so no font file ships and Turkish diacritics
    /// keep working. Row and control text stays SF Pro: serif at body size in a dense
    /// settings list costs legibility for no gain.
    enum Typography {
        /// Heading above a settings group ("Stil", "Zamanlama").
        static let groupTitle: Font = .system(.title3, design: .serif).weight(.semibold)
        /// Heading for a panel or inspector ("Canlı Önizleme").
        static let panelTitle: Font = .system(.headline, design: .serif)
        /// Title in a full-pane empty state.
        static let emptyStateTitle: Font = .system(.title2, design: .serif).weight(.semibold)
    }

    /// Readable max width for a settings content column on wide windows.
    static let contentMaxWidth: CGFloat = 620
    /// Standard sidebar icon-tile edge.
    static let tileSize: CGFloat = 26
    /// Short centered rule separating a quote from its attribution.
    static let ruleWidth: CGFloat = 120
}
