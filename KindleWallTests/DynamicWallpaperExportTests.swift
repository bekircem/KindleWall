import XCTest
@testable import KindleWall

/// Writes a full-resolution dynamic wallpaper to a fixed path so it can be applied to the real
/// desktop and inspected by eye. Not an assertion-heavy test — it exists so the pipeline can be
/// verified end to end against macOS itself, which no unit test can do.
final class DynamicWallpaperExportTests: XCTestCase {

    func test_exportFullResolutionDynamicWallpaper() throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KindleWallDynamicExport")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let screen = try XCTUnwrap(NSScreen.main)
        let size = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                          height: screen.frame.height * screen.backingScaleFactor)

        let clipping = Clipping(
            bookTitle: "Doğanın Sesi",
            author: "Baba Dioum",
            text: "İnsan ancak sevdiği şeyi korur, ancak anladığı şeyi sever."
        )

        let generator = WallpaperGenerator()
        let style = WallpaperStyle.forestLight
        let background = try XCTUnwrap(generator.renderBackgroundLayer(
            clipping: clipping, style: style, screenSize: size, typography: .default))
        let text = try XCTUnwrap(generator.renderTextLayer(
            clipping: clipping, style: style, screenSize: size,
            typography: .default, longQuote: .default))

        let phaseTimes = SunCalculator().phases(for: Date(), at: GeoCoordinate.fromSystemTimeZone())
        let frames = DynamicWallpaperComposer().compose(
            background: background, text: text, style: style, phases: phaseTimes.map(\.phase))
        XCTAssertEqual(frames.count, phaseTimes.count)

        let url = outputDir.appendingPathComponent("kindlewall_dynamic.heic")
        try HEICWallpaperEncoder().write(frames: frames, phaseTimes: phaseTimes, to: url)

        // Also write each frame as a PNG so the day's progression can be looked at directly.
        for (index, phaseTime) in phaseTimes.enumerated() {
            let png = outputDir.appendingPathComponent("frame_\(index)_\(phaseTime.phase.rawValue).png")
            try NSBitmapImageRep(cgImage: frames[index])
                .representation(using: .png, properties: [:])?
                .write(to: png)
        }

        let bytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        print("DYNAMIC EXPORT: \(url.path)")
        print("DYNAMIC SIZE: \(Int(truncating: bytes ?? 0)) bayt, \(frames.count) kare, \(Int(size.width))x\(Int(size.height))")
        for phaseTime in phaseTimes {
            print("DYNAMIC PHASE: \(phaseTime.phase.rawValue) -> \(phaseTime.date)")
        }
    }
}
