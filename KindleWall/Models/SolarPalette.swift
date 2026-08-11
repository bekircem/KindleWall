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
        /// ink. A discrete swap, used only when the background has moved far enough that the
        /// normal ink could not be read — never a gradual fade between the two.
        let usesInvertedInk: Bool
    }

    /// Contrast a frame's text must keep against its background before the ink is swapped.
    /// 4.5:1 is the WCAG AA threshold; wallpaper quotes are set large, so this is comfortably
    /// conservative — which is the point, since an unreadable wallpaper is a bug the user sees
    /// every time they look at their screen.
    static let minimumContrast = 4.5

    /// Builds the transforms for one phase of one style.
    ///
    /// - Parameters:
    ///   - phase: Which moment of the day.
    ///   - style: The style being rendered.
    ///   - typography: The user's settings, because a custom gradient replaces the style's own
    ///     surface entirely. Deciding the ink from the *style's* colour while the screen shows
    ///     the *gradient* meant the swap fired on a colour that was not there.
    static func transforms(for phase: SolarPhase,
                           style: WallpaperStyle,
                           typography: TypographySettings = .default) -> FrameTransforms {
        let cacheKey = "\(phase.rawValue)|\(style.rawValue)|\(typography.backgroundStartColorHex ?? "-")|\(typography.backgroundEndColorHex ?? "-")"
        cacheLock.lock()
        if let cached = cache[cacheKey] { cacheLock.unlock(); return cached }
        cacheLock.unlock()

        let base = curve[phase] ?? (kelvin: 6500, exposure: 0)
        let tune = tuning(for: style)

        // Scale the curve toward neutral by the style's warmth, and clamp the darkening so a
        // style never drops below its floor.
        let kelvin = 6500 + (base.kelvin - 6500) * tune.warmth
        let rawExposure = base.exposure * tune.lift / 0.45   // 0.45 keeps `lift` readable as ~1.0 = full swing
        let floorStops = log2(max(tune.floor, 0.01))
        let backgroundExposure = max(rawExposure, floorStops)

        // Decide the ink — and if necessary adjust the exposure — from the colour the background
        // will *actually* be, run through the very same Core Image chain the frame uses.
        let surface = WallpaperGenerator.backgroundColor(for: style, typography: typography)
        let normalInk = WallpaperGenerator.inkColor(for: style, typography: typography, inverted: false)
        let invertedInk = WallpaperGenerator.inkColor(for: style, typography: typography, inverted: true)

        let readable = readableExposure(intended: backgroundExposure, kelvin: kelvin,
                                        surface: surface, normalInk: normalInk,
                                        invertedInk: invertedInk)

        let result = FrameTransforms(
            background: Transform(kelvin: kelvin, exposure: readable.exposure),
            usesInvertedInk: readable.inverted
        )

        cacheLock.lock()
        cache[cacheKey] = result
        cacheLock.unlock()
        return result
    }

    /// Moves the background exposure until one of the two inks is genuinely readable on it, and
    /// reports which ink that is.
    ///
    /// This guard used to model the exposure as `luminance × 2^ev` and ignore the temperature
    /// shift entirely. `CIExposureAdjust` works in linear light, so the model was badly wrong in
    /// the dark: Paper's intended night exposure (−1.73 stops) does not produce the near-black it
    /// predicted but a mid-brown, RGB (0.62, 0.52, 0.33). Measured on that surface the warm ink
    /// scores 3.7:1 and white 3.6:1 — Paper has a **dead zone** from roughly −1.4 to −2.2 stops
    /// where *neither* ink is readable. The old guard aimed straight into it and then confidently
    /// picked white, which is what shipped as "the evening frames are unreadable".
    ///
    /// The search walks outward from the intended exposure and takes the first readable value, so
    /// a frame moves the smallest distance from its designed look that legibility allows. It
    /// walks in the direction the phase was already heading first, so a night frame gets darker
    /// (and flips to light ink) rather than being dragged back toward daylight.
    private static func readableExposure(intended: Double, kelvin: Double, surface: NSColor,
                                         normalInk: NSColor, invertedInk: NSColor)
        -> (exposure: Double, inverted: Bool) {

        func evaluate(_ exposure: Double) -> (score: Double, inverted: Bool) {
            let resolved = SolarColorTransform.resolve(
                surface, through: Transform(kelvin: kelvin, exposure: exposure)
            )
            let normal = SolarColorTransform.contrastRatio(normalInk, resolved)
            let inverse = SolarColorTransform.contrastRatio(invertedInk, resolved)
            // A swap only ever happens when the alternative is genuinely better, so a frame never
            // trades a readable combination for a worse one.
            return inverse > normal ? (inverse, true) : (normal, false)
        }

        let atIntended = evaluate(intended)
        if atIntended.score >= minimumContrast { return (intended, atIntended.inverted) }

        // Bounds: far enough to escape the dead zone in either direction, not so far that a
        // frame becomes a flat black or a blown-out white.
        let lowerBound = -5.0, upperBound = 0.5
        let step = 0.1
        // Continue the direction the phase intended: a darkening phase keeps darkening.
        let directions: [Double] = intended <= 0 ? [-1, 1] : [1, -1]

        // The intended direction is searched to exhaustion *before* the opposite one is tried at
        // all. Interleaving them by distance looks fairer but gets the design wrong: Paper's
        // night frame is 0.4 stops from a readable brighter exposure and 0.5 from a readable
        // darker one, so the nearest-first rule dragged night back toward daylight and kept the
        // dark ink — losing the whole point of the phase, which is that Paper turns over after
        // dark and its text goes light.
        for direction in directions {
            for i in 1...30 {
                let candidate = intended + direction * Double(i) * step
                guard candidate >= lowerBound, candidate <= upperBound else { break }
                let result = evaluate(candidate)
                if result.score >= minimumContrast { return (candidate, result.inverted) }
            }
        }

        // Nothing in range clears the bar — keep the intended look with the better of the two
        // inks rather than distorting the frame for no gain.
        return (intended, atIntended.inverted)
    }

    /// Memoised because the ink decision now costs a (tiny) Core Image render, and the apply
    /// path asks for the same phase/style pair twice — once to decide whether the inverted text
    /// layer is worth drawing at all, once per frame.
    nonisolated(unsafe) private static var cache: [String: FrameTransforms] = [:]
    private static let cacheLock = NSLock()

    /// Drops the memoised decisions. Only needed by tests that vary inputs the key does not
    /// cover; production inputs are all in the key.
    static func resetCache() {
        cacheLock.lock(); cache.removeAll(); cacheLock.unlock()
    }

    /// The ink colour a frame will actually use — the same value `WallpaperGenerator` draws.
    static func inkColor(for style: WallpaperStyle, inverted: Bool) -> NSColor {
        WallpaperGenerator.inkColor(for: style, typography: .default, inverted: inverted)
    }

    /// Representative background colour per style — the flat fill, or the gradient's midpoint.
    static func representativeBackground(for style: WallpaperStyle) -> NSColor {
        WallpaperGenerator.backgroundColor(for: style, typography: .default)
    }

    /// Representative text colour per style, matching `WallpaperGenerator`.
    static func representativeText(for style: WallpaperStyle) -> NSColor {
        WallpaperGenerator.inkColor(for: style, typography: .default, inverted: false)
    }
}
