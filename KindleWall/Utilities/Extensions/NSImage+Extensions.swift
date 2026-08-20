import AppKit

extension NSImage {
    /// Saves the image as a PNG file at the specified URL.
    /// - Parameter url: The file URL to save the PNG data to.
    /// - Throws: An error if the image cannot be converted or written.
    ///
    /// Encodes the PNG directly from an existing `NSBitmapImageRep` (which `render(size:)`
    /// attaches at exact pixel size) — avoiding the large `tiffRepresentation` intermediate
    /// copy a full-resolution wallpaper would otherwise allocate. Falls back to a CGImage
    /// snapshot for images created some other way.
    func savePNG(to url: URL) throws {
        let bitmapRep: NSBitmapImageRep
        if let rep = representations.lazy.compactMap({ $0 as? NSBitmapImageRep }).first {
            bitmapRep = rep
        } else if let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) {
            bitmapRep = NSBitmapImageRep(cgImage: cg)
        } else {
            throw KindleWallError.wallpaperGenerationFailed(reason: String(localized: "PNG conversion failed"))
        }

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw KindleWallError.wallpaperGenerationFailed(reason: String(localized: "PNG conversion failed"))
        }
        try pngData.write(to: url)
    }

    /// Creates an NSImage with the specified size and drawing handler.
    /// - Parameters:
    ///   - size: The size of the image, interpreted as **exact pixels** (1pt = 1px).
    ///   - drawing: A closure that performs drawing operations in the current graphics context.
    /// - Returns: The rendered NSImage, or nil if rendering fails.
    ///
    /// Renders into a fixed-size `NSBitmapImageRep` rather than `lockFocus()`. `lockFocus`
    /// allocates a backing store at the *display's* backing scale, so an image already sized in
    /// device pixels (points × backingScaleFactor) was rendered — and PNG-encoded — at 4× the
    /// pixels actually needed. This path produces exactly `size` pixels. The bitmap context is
    /// non-flipped (origin bottom-left), matching the previous `lockFocus` orientation, and is
    /// pushed as `NSGraphicsContext.current` so `NSAttributedString.draw` keeps working.
    static func render(size: CGSize, drawing: (CGContext) -> Void) -> NSImage? {
        let pixelsWide = Int(size.width.rounded())
        let pixelsHigh = Int(size.height.rounded())
        guard pixelsWide > 0, pixelsHigh > 0 else { return nil }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        // Report 1pt = 1px so no implicit scaling happens on display or PNG encode.
        rep.size = NSSize(width: pixelsWide, height: pixelsHigh)

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        drawing(context.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: pixelsWide, height: pixelsHigh))
        image.addRepresentation(rep)
        return image
    }
}
