import AppKit
import CoreImage

// MARK: - Protocol

/// Turns the two rendered layers into one frame per solar phase.
protocol DynamicWallpaperComposerProtocol {
    /// Composites background and text for every phase, applying that phase's colour transforms.
    /// - Parameters:
    ///   - background: Opaque background layer.
    ///   - text: Transparent text/decoration layer, same pixel size as `background`.
    ///   - style: Style being rendered — selects the palette tuning.
    ///   - phases: Phases to render, in order.
    /// - Returns: One image per phase, in the same order; empty if compositing failed.
    func compose(background: NSImage, text: NSImage,
                 style: WallpaperStyle, phases: [SolarPhase]) -> [CGImage]
}

// MARK: - Implementation

/// Produces the day's frames from a single pair of rendered layers.
///
/// Both layers are rendered once; each frame is then only a pair of colour transforms and a
/// composite, which is GPU work. Measured on a 3840×2560 screen: two layer renders ≈ 70 ms,
/// six frames ≈ 244 ms — versus six full re-renders, where the font-fitting and typesetting
/// would be repeated every time.
final class DynamicWallpaperComposer: DynamicWallpaperComposerProtocol {

    private let context: CIContext

    init(context: CIContext = CIContext(options: [.useSoftwareRenderer: false])) {
        self.context = context
    }

    func compose(background: NSImage, text: NSImage,
                 style: WallpaperStyle, phases: [SolarPhase]) -> [CGImage] {
        guard let backgroundCG = background.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let textCG = text.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let backgroundCI = CIImage(cgImage: backgroundCG)
        let textCI = CIImage(cgImage: textCG)
        let extent = backgroundCI.extent

        return phases.compactMap { phase in
            if Task.isCancelled { return nil }
            let transforms = SolarPalette.transforms(for: phase, style: style)
            let tintedBackground = apply(transforms.background, to: backgroundCI, hasAlpha: false)
            let tintedText = apply(transforms.text, to: textCI, hasAlpha: true)
            let composited = tintedText.composited(over: tintedBackground)

            // Render without an alpha channel. The composite is fully opaque, but keeping the
            // alpha made ImageIO warn that it "will double (!!!) the required memory when
            // decoding" — at 3840×2560 × 6 frames that is hundreds of megabytes of waste per
            // apply, and it inflates the file too.
            return context.createCGImage(
                composited,
                from: extent,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                deferred: false
            ).flatMap(Self.droppingAlpha)
        }
    }

    /// Re-draws the image into an opaque bitmap, discarding the (fully opaque) alpha channel.
    private static func droppingAlpha(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    /// Applies one phase's temperature and exposure to a layer.
    ///
    /// Alpha layers are un-premultiplied first: Core Image colour filters operate on
    /// premultiplied RGB, so brightening the text layer directly would push colour values past
    /// their own alpha and fringe the glyph edges.
    private func apply(_ transform: SolarPalette.Transform, to image: CIImage, hasAlpha: Bool) -> CIImage {
        let source = hasAlpha ? image.unpremultiplyingAlpha() : image

        // Direction matters and is easy to get backwards: `inputNeutral` is the white point the
        // source is assumed to have, `inputTargetNeutral` the one it should be rendered at. The
        // layers are authored at neutral daylight, so 6500 K is the source; pushing the *target*
        // down to 3200 K is what makes a frame look like golden hour. Swapping the two tints
        // sunrise blue instead of amber.
        let warmed = source.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(x: transform.kelvin, y: 0)
        ])
        let exposed = warmed.applyingFilter("CIExposureAdjust", parameters: [
            "inputEV": transform.exposure
        ])

        return hasAlpha ? exposed.premultiplyingAlpha() : exposed
    }
}
