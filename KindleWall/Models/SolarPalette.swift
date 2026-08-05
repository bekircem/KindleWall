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

    /// Background and text transforms for a phase, already checked for legibility.
    struct FrameTransforms: Equatable {
        let background: Transform
        let text: Transform
    }

    /// Minimum background/text luminance separation. Below this the frame is unreadable;
    /// the text transform is pulled back until it clears.
    private static let minimumLuminanceGap = 0.35

    /// Builds the transforms for one phase of one style.
    ///
    /// Legibility is settled here, on two representative colours, *before* any pixels are
    /// touched — so an unreadable frame is never rendered and then discarded.
    /// - Parameters:
    ///   - phase: Which moment of the day.
    ///   - style: The style being rendered.
    /// - Returns: Transforms for the background and text layers.
    static func transforms(for phase: SolarPhase, style: WallpaperStyle) -> FrameTransforms {
        let base = curve[phase] ?? (kelvin: 6500, exposure: 0)
        let tune = tuning(for: style)

        // Scale the curve toward neutral by the style's warmth, and clamp the darkening so a
        // style never drops below its floor.
        let kelvin = 6500 + (base.kelvin - 6500) * tune.warmth
        let rawExposure = base.exposure * tune.lift / 0.45   // 0.45 keeps `lift` readable as ~1.0 = full swing
        let floorStops = log2(max(tune.floor, 0.01))
        let backgroundExposure = max(rawExposure, floorStops)

        // Light styles flip at night: the background darkens past the text, so the text has to
        // brighten to stay readable. That was the explicit design choice for Paper.
        let flips = style.hasLightBackground && phase == .night
        let textExposure = flips
            ? -backgroundExposure + 1.6
            : -backgroundExposure * 0.55

        var transforms = FrameTransforms(
            background: Transform(kelvin: kelvin, exposure: backgroundExposure),
            text: Transform(kelvin: kelvin, exposure: textExposure)
        )

        // Verify on representative colours and pull the text back if the gap is too small.
        transforms = enforcingContrast(transforms, style: style)
        return transforms
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

    private static func enforcingContrast(_ transforms: FrameTransforms,
                                          style: WallpaperStyle) -> FrameTransforms {
        let background = representativeBackground(for: style)
        let text = representativeText(for: style)

        var textExposure = transforms.text.exposure
        let backgroundLuminance = adjustedLuminance(background, exposure: transforms.background.exposure)

        // Push the text away from the background — brighter on dark backgrounds, darker on
        // light ones — until the gap clears, in small steps so the look degrades gracefully.
        for _ in 0..<24 {
            let textLuminance = adjustedLuminance(text, exposure: textExposure)
            if abs(textLuminance - backgroundLuminance) >= minimumLuminanceGap { break }
            textExposure += backgroundLuminance < 0.5 ? 0.15 : -0.15
        }

        return FrameTransforms(
            background: transforms.background,
            text: Transform(kelvin: transforms.text.kelvin, exposure: textExposure)
        )
    }
}
