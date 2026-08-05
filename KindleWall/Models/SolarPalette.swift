import AppKit

/// How a wallpaper style's colours move across the day.
///
/// Rather than hand-painting a palette per style per phase (six styles × six phases = 36
/// palettes to design and maintain), one curve is applied to every style and each style tunes
/// it with three numbers. Adding a style therefore costs three numbers, not six palettes.
struct SolarPalette {

    /// Per-style tuning of the shared curve.
    struct Tuning {
        /// How strongly the colour temperature swings. 0 = stays neutral all day.
        let warmth: Double
        /// How strongly brightness swings between noon and night.
        let lift: Double
        /// Lowest brightness multiplier the background may reach, so nothing goes to mud.
        let floor: Double
    }

    /// Colour temperature (Kelvin) and exposure offset for each phase, before per-style tuning.
    /// 6500K is neutral daylight; the golden hours dip warm and night goes cool.
    private static let curve: [SolarPhase: (kelvin: Double, exposure: Double)] = [
        .dawn:      (5600, -0.85),
        .sunrise:   (3200, -0.30),
        .noon:      (6500,  0.00),
        .afternoon: (5200, -0.10),
        .sunset:    (2900, -0.35),
        .night:     (4200, -1.30)
    ]

    static func tuning(for style: WallpaperStyle) -> Tuning {
        switch style {
        // Night's identity is that it stays dark — a big swing would turn it grey at noon.
        case .night:       return Tuning(warmth: 0.40, lift: 0.15, floor: 0.55)
        // Paper is the only light style, so it has the most room to move and the most to gain.
        case .paper:       return Tuning(warmth: 1.00, lift: 0.60, floor: 0.22)
        // Grid is deliberately clinical; warmth would fight the technical character.
        case .grid:        return Tuning(warmth: 0.25, lift: 0.20, floor: 0.50)
        case .dawn:        return Tuning(warmth: 0.80, lift: 0.45, floor: 0.35)
        case .depth:       return Tuning(warmth: 0.45, lift: 0.40, floor: 0.35)
        // The radial shaft is the showpiece: warmth and intensity both move.
        case .forestLight: return Tuning(warmth: 0.85, lift: 0.50, floor: 0.30)
        }
    }

    /// The transform applied to one layer for one phase.
    struct Transform: Equatable {
        /// Target neutral for `CITemperatureAndTint`, in Kelvin.
        let kelvin: Double
        /// Exposure offset in stops for `CIExposureAdjust`.
        let exposure: Double
    }

    /// What one phase does to a frame.
    ///
    /// Only the background is colour-transformed. The text keeps exactly the colour it was
    /// drawn with — an earlier version moved it on an inverse curve, and because both layers
    /// also took the same warmth shift, the background and the ink converged as the day went
    /// on: by sunset a Paper wallpaper was brown text on brown paper. Time of day changes the
    /// light in the room, not the ink on the page.
    struct FrameTransforms: Equatable {
        let background: Transform

        /// Whether this frame draws the style's inverted ink (light text) instead of its normal
        /// ink. A discrete swap, used only when the background has darkened far enough that the
        /// normal ink could not be read — never a gradual fade between the two.
        let usesInvertedInk: Bool
    }

    /// Luminance below which a light style's dark ink stops being readable and the frame swaps
    /// to the inverted ink.
    private static let inkFlipThreshold = 0.42

    /// Builds the transforms for one phase of one style.
    /// - Parameters:
    ///   - phase: Which moment of the day.
    ///   - style: The style being rendered.
    /// - Returns: The background transform and which ink the text layer should use.
    static func transforms(for phase: SolarPhase, style: WallpaperStyle) -> FrameTransforms {
        let base = curve[phase] ?? (kelvin: 6500, exposure: 0)
        let tune = tuning(for: style)

        // Scale the curve toward neutral by the style's warmth, and clamp the darkening so a
        // style never drops below its floor.
        let kelvin = 6500 + (base.kelvin - 6500) * tune.warmth
        let rawExposure = base.exposure * tune.lift / 0.45   // 0.45 keeps `lift` readable as ~1.0 = full swing
        let floorStops = log2(max(tune.floor, 0.01))
        let backgroundExposure = max(rawExposure, floorStops)

        let background = Transform(kelvin: kelvin, exposure: backgroundExposure)

        // Decide the ink from where the background actually ended up, not from the phase name:
        // a light style whose background has gone dark needs light ink, and a dark style never
        // brightens enough to need dark ink.
        let backgroundLuminance = adjustedLuminance(
            representativeBackground(for: style), exposure: backgroundExposure
        )
        let inverted = style.hasLightBackground && backgroundLuminance < inkFlipThreshold

        return FrameTransforms(background: background, usesInvertedInk: inverted)
    }

    /// The ink colour a frame will actually use — the same value `WallpaperGenerator` draws.
    static func inkColor(for style: WallpaperStyle, inverted: Bool) -> NSColor {
        let onLight = inverted ? !style.hasLightBackground : style.hasLightBackground
        return onLight ? NSColor(hex: "3B2F1E")! : .white
    }

    /// Approximate luminance after an exposure adjustment, in 0...1.
    private static func adjustedLuminance(_ color: NSColor, exposure: Double) -> Double {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return 0.5 }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return min(max(Double(luminance) * pow(2, exposure), 0), 1)
    }

    /// Representative background colour per style — the flat fill, or the gradient's midpoint.
    static func representativeBackground(for style: WallpaperStyle) -> NSColor {
        switch style {
        case .night:       return NSColor(hex: "141414")!
        case .paper:       return NSColor(hex: "F4E8C1")!
        case .grid:        return NSColor(hex: "0D1117")!
        case .dawn:        return NSColor(hex: "E0453A")!
        case .depth:       return NSColor(hex: "764BA2")!
        case .forestLight: return NSColor(hex: "17330F")!
        }
    }

    /// Representative text colour per style, matching `WallpaperGenerator.textColor`.
    static func representativeText(for style: WallpaperStyle) -> NSColor {
        style.hasLightBackground ? NSColor(hex: "3B2F1E")! : .white
    }

}
