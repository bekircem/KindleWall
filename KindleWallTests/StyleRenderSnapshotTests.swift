import XCTest
@testable import KindleWall

/// Renders every wallpaper style and writes the results to disk so they can be inspected
/// by eye. This exists because the P0.1 change swapped `lockFocus()` for a fixed-size
/// `NSBitmapImageRep`, and nobody has looked at the output since. It also asserts the
/// mechanical properties that change would break: exact pixel size, correct orientation,
/// and a background colour matching the style's declared hex.
final class StyleRenderSnapshotTests: XCTestCase {
    /// Where the rendered PNGs land. Printed by the test so a human can open them.
    private static let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("KindleWallStyleSnapshots")

    private let generator = WallpaperGenerator()
    private let size = CGSize(width: 1280, height: 800)

    private var clipping: Clipping {
        Clipping(
            id: Clipping.deterministicID(bookTitle: "Doğanın Sesi", text: "sabit"),
            bookTitle: "Doğanın Sesi",
            author: "Baba Dioum",
            text: "İnsan ancak sevdiği şeyi korur, ancak anladığı şeyi sever."
        )
    }

    override class func setUp() {
        try? FileManager.default.removeItem(at: outputDir)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    /// Reads one pixel out of the rendered image. `y` is measured from the TOP of the image,
    /// which is what a human means when they say "top-left corner".
    private func pixel(_ image: NSImage, x: Int, yFromTop: Int) throws -> NSColor {
        let rep = try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        return try XCTUnwrap(rep.colorAt(x: x, y: yFromTop))
    }

    func test_everyStyleRendersAtExactPixelSizeAndWritesSnapshot() throws {
        for style in WallpaperStyle.allCases {
            let image = try XCTUnwrap(
                generator.generateWallpaper(clipping: clipping, style: style, screenSize: size),
                "\(style.rawValue) hiç render edilmedi"
            )

            // P0.1's whole point: 1pt == 1px, no backing-scale multiplication.
            let rep = try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
            XCTAssertEqual(rep.pixelsWide, Int(size.width), "\(style.rawValue) genişliği yanlış")
            XCTAssertEqual(rep.pixelsHigh, Int(size.height), "\(style.rawValue) yüksekliği yanlış")

            let url = Self.outputDir.appendingPathComponent("\(style.rawValue).png")
            try image.savePNG(to: url)
        }
        print("SNAPSHOT DIR: \(Self.outputDir.path)")
    }

    /// The corner is outside the text block for every style, so it reports the background.
    /// Wrong values here mean the bitmap context's colour space is mangling the palette.
    func test_backgroundCornerMatchesDeclaredStyleColor() throws {
        let expected: [WallpaperStyle: (r: CGFloat, g: CGFloat, b: CGFloat)] = [
            .night: (0x14 / 255, 0x14 / 255, 0x14 / 255),
            .grid:  (0x0D / 255, 0x11 / 255, 0x17 / 255)
        ]

        for (style, want) in expected {
            let image = try XCTUnwrap(
                generator.generateWallpaper(clipping: clipping, style: style, screenSize: size)
            )
            let c = try pixel(image, x: 4, yFromTop: 4).usingColorSpace(.deviceRGB)!
            XCTAssertEqual(c.redComponent,   want.r, accuracy: 0.02, "\(style.rawValue) kırmızı kanalı kaymış")
            XCTAssertEqual(c.greenComponent, want.g, accuracy: 0.02, "\(style.rawValue) yeşil kanalı kaymış")
            XCTAssertEqual(c.blueComponent,  want.b, accuracy: 0.02, "\(style.rawValue) mavi kanalı kaymış")
        }
    }

    /// `dawn` runs orange (top-left) to dark red (bottom-right). If the bitmap context were
    /// flipped relative to the old `lockFocus` behaviour, these two swap — which is exactly
    /// how mirrored/upside-down text would show up.
    func test_gradientOrientationIsNotFlipped() throws {
        let image = try XCTUnwrap(
            generator.generateWallpaper(clipping: clipping, style: .dawn, screenSize: size)
        )
        let topLeft = try pixel(image, x: 8, yFromTop: 8).usingColorSpace(.deviceRGB)!
        let bottomRight = try pixel(image, x: Int(size.width) - 8, yFromTop: Int(size.height) - 8)
            .usingColorSpace(.deviceRGB)!

        XCTAssertGreaterThan(topLeft.redComponent, bottomRight.redComponent,
                             "gradient ters dönmüş: sol üst, sağ alttan daha koyu")
        XCTAssertGreaterThan(topLeft.greenComponent, bottomRight.greenComponent,
                             "gradient ters dönmüş: sol üst turuncu olmalı")
    }
}
