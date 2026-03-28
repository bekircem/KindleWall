import AppKit

extension NSImage {
    /// Saves the image as a PNG file at the specified URL.
    /// - Parameter url: The file URL to save the PNG data to.
    /// - Throws: An error if the image cannot be converted or written.
    func savePNG(to url: URL) throws {
        guard let tiffData = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw KindleWallError.wallpaperGenerationFailed(reason: "PNG dönüşümü başarısız")
        }
        try pngData.write(to: url)
    }

    /// Creates an NSImage with the specified size and drawing handler.
    /// - Parameters:
    ///   - size: The size of the image.
    ///   - drawing: A closure that performs drawing operations in the current graphics context.
    /// - Returns: The rendered NSImage, or nil if rendering fails.
    static func render(size: CGSize, drawing: (CGContext) -> Void) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }
        drawing(context)
        image.unlockFocus()
        return image
    }
}
