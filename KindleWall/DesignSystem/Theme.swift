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
        static let accent = Color.accentColor
        /// Subtle elevated surface for cards on the dark canvas.
        static let cardFill = Color.white.opacity(0.05)
        /// Hairline border around cards.
        static let cardStroke = Color.white.opacity(0.09)
        /// Inset divider between rows inside a card.
        static let rowDivider = Color.white.opacity(0.06)
        /// Hover highlight for interactive rows / cards.
        static let hover = Color.white.opacity(0.07)
    }

    /// Shared animation presets so transitions feel coherent across screens.
    /// `snappy` for selections/toggles, `smooth` for content/layout changes,
    /// `hover` for lightweight pointer feedback.
    enum Motion {
        static let snappy: Animation = .snappy(duration: 0.28)
        static let smooth: Animation = .smooth(duration: 0.32)
        static let hover: Animation = .easeOut(duration: 0.15)
    }

    /// Readable max width for a settings content column on wide windows.
    static let contentMaxWidth: CGFloat = 620
    /// Standard sidebar icon-tile edge.
    static let tileSize: CGFloat = 26
}
