import AppKit
import CoreImage

// MARK: - Protocol

/// Turns the two rendered layers into one frame per solar phase.
/// `Sendable`: frame composition runs on the off-main render path.
protocol DynamicWallpaperComposerProtocol: Sendable {
    /// Prepares the shared, expensive setup once and returns a closure that produces **one frame
    /// per call**.
    ///
    /// Streaming rather than returning `[CGImage]`: at 3840×2560 a frame is 39 MB, so holding all
    /// six alive until the HEIC encode finished cost ~236 MB per apply on top of the layers —
    /// and the old opaque-copy step briefly doubled that again.
    ///
    /// - Parameters:
    ///   - background: Opaque background layer.
    ///   - text: Transparent text/decoration layer in the style's normal ink.
    ///   - invertedText: The same layer drawn in the opposite ink, for phases whose background
    ///     has moved past readability. Pass nil when no phase needs it.
    ///   - style: Style being rendered — selects the palette tuning.
    ///   - typography: User settings, because a custom gradient changes which ink a phase needs.
    /// - Returns: A frame factory, or nil if the layers could not be read.
    func makeFrameSource(background: NSImage, text: NSImage, invertedText: NSImage?,
                         style: WallpaperStyle,
                         typography: TypographySettings) -> ((SolarPhase) -> CGImage?)?
}

extension DynamicWallpaperComposerProtocol {
    /// Convenience for one-shot callers and tests. The apply path uses `makeFrameSource`
    /// directly so it never holds more than one frame in memory.
    func compose(background: NSImage, text: NSImage, invertedText: NSImage?,
                 style: WallpaperStyle, phases: [SolarPhase],
                 typography: TypographySettings = .default) -> [CGImage] {
        guard let source = makeFrameSource(background: background, text: text,
                                           invertedText: invertedText, style: style,
                                           typography: typography) else { return [] }
        return phases.compactMap(source)
    }
}

// MARK: - Implementation

/// Produces the day's frames from a single pair of rendered layers.
///
/// Both layers are rendered once; each frame is then only a colour transform and a composite,
/// which is GPU work. Measured on a 3840×2560 screen: two layer renders ≈ 70 ms, six frames
/// ≈ 244 ms — versus six full re-renders, where the font-fitting and typesetting would be
/// repeated every time.
final class DynamicWallpaperComposer: DynamicWallpaperComposerProtocol {

    private let context: CIContext

    /// Defaults to the app-wide context. Creating a `CIContext` allocates Metal resources, and a
    /// per-instance one meant every apply paid to set the GPU pipeline up again.
    init(context: CIContext = SolarColorTransform.context) {
        self.context = context
    }

    func makeFrameSource(background: NSImage, text: NSImage, invertedText: NSImage?,
                         style: WallpaperStyle,
                         typography: TypographySettings = .default) -> ((SolarPhase) -> CGImage?)? {
        guard let backgroundCG = background.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let textCG = text.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let backgroundCI = CIImage(cgImage: backgroundCG)
        let textCI = CIImage(cgImage: textCG)
        let invertedTextCI = invertedText
            .flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
            .map { CIImage(cgImage: $0) }
        let extent = backgroundCI.extent
        let context = self.context

        return { phase in
            if Task.isCancelled { return nil }
            let transforms = SolarPalette.transforms(for: phase, style: style, typography: typography)

            // Only the background is transformed. The text is composited exactly as drawn —
            // tinting it alongside the background made the two converge, and by sunset a Paper
            // wallpaper was brown text on brown paper.
            let tintedBackground = SolarColorTransform.apply(transforms.background, to: backgroundCI)
            let ink = (transforms.usesInvertedInk ? invertedTextCI : nil) ?? textCI
            let composited = ink.composited(over: tintedBackground)

            // Render straight into an opaque bitmap. The composite is fully opaque anyway, and
            // keeping an alpha channel made ImageIO warn that it "will double (!!!) the required
            // memory when decoding" — at 3840×2560 × 6 frames, hundreds of megabytes of waste per
            // apply, plus a fatter file for the system to decode on every Space.
            //
            // This used to be done by rendering an RGBA8 CGImage and then re-drawing it into an
            // opaque context: two full-size buffers per frame for something one render can do.
            return Perf.measure("frame.compose", "\(phase.rawValue)") { () -> CGImage? in
                guard let out = CGContext(
                    data: nil,
                    width: Int(extent.width),
                    height: Int(extent.height),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ) else { return nil }

                // Force-unwrapping `out.data` would trade a missing frame for a crash. The
                // caller already knows how to handle nil here — it falls back to the static
                // wallpaper — so a desktop that changes beats a dialog that does not.
                guard let bitmap = out.data else { return nil }

                context.render(composited,
                               toBitmap: bitmap,
                               rowBytes: out.bytesPerRow,
                               bounds: extent,
                               format: .RGBA8,
                               colorSpace: CGColorSpaceCreateDeviceRGB())
                return out.makeImage()
            }
        }
    }
}
