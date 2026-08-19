import SwiftUI

/// A rounded-rectangle icon tile with a gradient fill and a legible glyph.
///
/// The Loop-style colored icon used in both the sidebar and settings rows.
/// Extracted into one component so the sidebar and content share identical icon treatment.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = Theme.tileSize

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(Self.glyph(on: color))
            .frame(width: size, height: size)
            .background(
                color.gradient,
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
    }

    /// White, unless white fails to read on `fill`.
    ///
    /// The glyph used to be hardcoded white, which is right for the cool tiles and wrong for
    /// the warm ones: white over the amber accent measures 1.9:1 and over system orange 2.1:1,
    /// both under WCAG's 3:1 floor for non-text marks.
    ///
    /// The floor, and not "whichever contrasts more", is deliberately the rule. Maximising
    /// contrast flips the *medium* fills too — system blue reads better under dark glyphs on
    /// paper arithmetic — and a dark glyph on a blue tile looks like a rendering bug next to
    /// every other Mac app. So convention holds until legibility actually breaks.
    ///
    /// Not private: `IconTileGlyphTests` pins this, and a tile with an illegible glyph still
    /// looks like a tile in a screenshot.
    static func glyph(on fill: Color) -> Color {
        guard let srgb = NSColor(fill).usingColorSpace(.sRGB) else { return .white }
        let whiteContrast = contrast(relativeLuminance(srgb), 1.0)
        return whiteContrast >= Self.nonTextContrastFloor ? .white : Theme.Palette.onAccent
    }

    /// WCAG 2.1 (1.4.11) minimum for graphical objects and UI components.
    static let nonTextContrastFloor: CGFloat = 3.0

    private static func relativeLuminance(_ c: NSColor) -> CGFloat {
        func lin(_ v: CGFloat) -> CGFloat {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.redComponent)
             + 0.7152 * lin(c.greenComponent)
             + 0.0722 * lin(c.blueComponent)
    }

    private static func contrast(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

#Preview {
    // Spans the range the glyph rule has to handle: dark fills keep a white glyph, the
    // light warm ones flip to dark.
    HStack(spacing: 12) {
        IconTile(symbol: "quote.bubble.fill", color: Theme.Palette.accent)
        IconTile(symbol: "books.vertical.fill", color: .teal)
        IconTile(symbol: "clock.fill", color: .blue)
        IconTile(symbol: "textformat", color: .pink)
        IconTile(symbol: "sun.max.fill", color: .orange)
        IconTile(symbol: "gearshape.fill", color: Color(.systemGray))
    }
    .padding()
    .preferredColorScheme(.dark)
}
