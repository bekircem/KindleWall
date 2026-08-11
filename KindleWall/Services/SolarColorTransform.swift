import AppKit
import CoreImage

/// The colour transform a solar phase applies to a wallpaper layer — in exactly one place.
///
/// It used to live in two. `DynamicWallpaperComposer` ran `CITemperatureAndTint` followed by
/// `CIExposureAdjust`, while the readability guard in `SolarPalette` approximated the same thing
/// as `luminance * pow(2, exposure)` and **ignored the temperature entirely**. For Paper at
/// sunset the target neutral is 2900 K, which moves the blue channel a long way, so the guard was
/// judging the frame on a colour the frame never had — and picking the wrong ink.
///
/// Now the guard renders a 1×1 image through the *same* filter chain. It costs microseconds and
/// it cannot drift from what the frames actually look like.
enum SolarColorTransform {

    /// One GPU context for the whole app. Creating a `CIContext` allocates Metal resources; doing
    /// it per apply is pure waste when every apply wants the same thing.
    static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Applies one phase's temperature and exposure to an image.
    ///
    /// Direction matters and is easy to get backwards: `inputNeutral` is the white point the
    /// source is assumed to have, `inputTargetNeutral` the one it should be rendered at. The
    /// layers are authored at neutral daylight, so 6500 K is the source; pushing the *target*
    /// down to 3200 K is what makes a frame look like golden hour. Swapping the two tints
    /// sunrise blue instead of amber.
    static func apply(_ transform: SolarPalette.Transform, to image: CIImage) -> CIImage {
        let warmed = image.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(x: transform.kelvin, y: 0)
        ])
        return warmed.applyingFilter("CIExposureAdjust", parameters: [
            "inputEV": transform.exposure
        ])
    }

    /// Runs a single colour through the same chain the frames use.
    /// - Returns: the transformed colour, or `color` unchanged if the render fails.
    static func resolve(_ color: NSColor, through transform: SolarPalette.Transform) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }
        let source = CIImage(color: CIColor(red: rgb.redComponent,
                                            green: rgb.greenComponent,
                                            blue: rgb.blueComponent))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(apply(transform, to: source),
                       toBitmap: &pixel,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        return NSColor(deviceRed: CGFloat(pixel[0]) / 255,
                       green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255,
                       alpha: 1)
    }

    /// Perceived luminance in 0…1, using the same weights as the rest of the app.
    static func luminance(_ color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return 0.5 }
        return 0.299 * Double(rgb.redComponent)
             + 0.587 * Double(rgb.greenComponent)
             + 0.114 * Double(rgb.blueComponent)
    }

    /// WCAG relative luminance — the input to a contrast ratio, which is not the same thing as
    /// the perceptual luminance above.
    static func relativeLuminance(_ color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return 0.5 }
        func channel(_ v: CGFloat) -> Double {
            let c = Double(v)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent)
             + 0.7152 * channel(rgb.greenComponent)
             + 0.0722 * channel(rgb.blueComponent)
    }

    /// WCAG contrast ratio between two colours, 1…21.
    static func contrastRatio(_ a: NSColor, _ b: NSColor) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
