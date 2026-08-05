import XCTest
import ImageIO
@testable import KindleWall

/// End-to-end checks for the dynamic pipeline: two layers in, a macOS-readable dynamic HEIC out.
final class DynamicWallpaperTests: XCTestCase {

    private var tempDir: URL!
    private let generator = WallpaperGenerator()
    private let composer = DynamicWallpaperComposer()
    private let encoder = HEICWallpaperEncoder()
    private let size = CGSize(width: 640, height: 400)

    private let clipping = Clipping(
        bookTitle: "Doğanın Sesi",
        author: "Baba Dioum",
        text: "İnsan ancak sevdiği şeyi korur, ancak anladığı şeyi sever."
    )

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KindleWallDynamic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func layers(style: WallpaperStyle) throws -> (background: NSImage, text: NSImage) {
        let background = try XCTUnwrap(generator.renderBackgroundLayer(
            clipping: clipping, style: style, screenSize: size, typography: .default))
        let text = try XCTUnwrap(generator.renderTextLayer(
            clipping: clipping, style: style, screenSize: size,
            typography: .default, longQuote: .default))
        return (background, text)
    }

    private func phaseTimes() -> [SolarPhaseTime] {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date())
        let hours: [Double] = [5.5, 6.5, 12, 16, 19, 21.5]
        return zip(SolarPhase.allCases, hours).map {
            SolarPhaseTime(phase: $0, date: midnight.addingTimeInterval($1 * 3600))
        }
    }

    // MARK: - Layers

    func test_textLayerIsTransparentWhereThereIsNoText() throws {
        let (_, text) = try layers(style: .night)
        let rep = try XCTUnwrap(text.representations.compactMap { $0 as? NSBitmapImageRep }.first)

        // Top-left corner sits well outside the centred quote block.
        let corner = try XCTUnwrap(rep.colorAt(x: 3, y: 3))
        XCTAssertEqual(corner.alphaComponent, 0, accuracy: 0.01,
                       "metin katmanının boş alanı saydam olmalı")
    }

    func test_backgroundLayerIsOpaque() throws {
        let (background, _) = try layers(style: .night)
        let rep = try XCTUnwrap(background.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        let corner = try XCTUnwrap(rep.colorAt(x: 3, y: 3))
        XCTAssertEqual(corner.alphaComponent, 1, accuracy: 0.01)
    }

    // MARK: - Composition

    func test_composerProducesOneFramePerPhase() throws {
        let (background, text) = try layers(style: .forestLight)
        let frames = composer.compose(background: background, text: text,
                                      style: .forestLight, phases: SolarPhase.allCases)

        XCTAssertEqual(frames.count, SolarPhase.allCases.count)
        for frame in frames {
            XCTAssertEqual(frame.width, Int(size.width))
            XCTAssertEqual(frame.height, Int(size.height))
        }
    }

    /// The point of the feature: the day's frames must not all look the same.
    func test_framesDifferAcrossTheDay() throws {
        let (background, text) = try layers(style: .forestLight)
        let frames = composer.compose(background: background, text: text,
                                      style: .forestLight, phases: [.noon, .night])
        XCTAssertEqual(frames.count, 2)

        let noon = averageLuminance(frames[0])
        let night = averageLuminance(frames[1])
        XCTAssertGreaterThan(noon - night, 0.05, "gece karesi öğlenden belirgin koyu olmalı")
    }

    /// Golden hours must run *warm*. `CITemperatureAndTint`'s two white-point arguments are
    /// easy to transpose, and transposing them tints sunrise blue — a bug that shipped once and
    /// was only caught by looking at the frames, since every other assertion still passed.
    func test_goldenHourFramesAreWarmerThanNoon() throws {
        let (background, text) = try layers(style: .forestLight)
        let frames = composer.compose(background: background, text: text,
                                      style: .forestLight, phases: [.noon, .sunset])
        XCTAssertEqual(frames.count, 2)

        let noon = averageChannels(frames[0])
        let sunset = averageChannels(frames[1])

        // Red rising relative to blue is what "warmer" means.
        XCTAssertGreaterThan(sunset.red - sunset.blue, noon.red - noon.blue,
                             "günbatımı karesi öğlenden daha sıcak olmalı (kırmızı-mavi farkı artmalı)")
    }

    // MARK: - Encoding

    func test_encodedFileIsAMultiImageHeicWithDynamicMetadata() throws {
        let (background, text) = try layers(style: .paper)
        let frames = composer.compose(background: background, text: text,
                                      style: .paper, phases: SolarPhase.allCases)
        let url = tempDir.appendingPathComponent("dynamic.heic")

        try encoder.write(frames: frames, phaseTimes: phaseTimes(), to: url)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), SolarPhase.allCases.count,
                       "konteyner altı kare içermeli")

        // The tag macOS reads. Without it the file is just a still image.
        let metadata = try XCTUnwrap(CGImageSourceCopyMetadataAtIndex(source, 0, nil))
        let tag = try XCTUnwrap(
            CGImageMetadataCopyTagWithPath(metadata, nil, "apple_desktop:h24" as CFString),
            "apple_desktop:h24 etiketi yazılmamış"
        )
        let value = try XCTUnwrap(CGImageMetadataTagCopyValue(tag) as? String)
        let decoded = try XCTUnwrap(Data(base64Encoded: value))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: decoded, format: nil) as? [String: Any]
        )
        let entries = try XCTUnwrap(plist["ti"] as? [[String: Any]])

        XCTAssertEqual(entries.count, SolarPhase.allCases.count)
        XCTAssertEqual(entries.map { $0["i"] as? Int }, Array(0..<SolarPhase.allCases.count),
                       "kare indeksleri sırayla 0..n olmalı")

        let times = entries.compactMap { $0["t"] as? Double }
        XCTAssertEqual(times, times.sorted(), "faz zamanları artan sırada olmalı")
        XCTAssertTrue(times.allSatisfy { $0 >= 0 && $0 < 1 }, "gün kesirleri 0..1 aralığında olmalı")
    }

    func test_encoderRejectsMismatchedFrameAndPhaseCounts() throws {
        let (background, text) = try layers(style: .night)
        let frames = composer.compose(background: background, text: text,
                                      style: .night, phases: [.noon])

        XCTAssertThrowsError(
            try encoder.write(frames: frames, phaseTimes: phaseTimes(),
                              to: tempDir.appendingPathComponent("bad.heic"))
        )
    }

    /// The reason for moving to HEIC at all: six dynamic frames must not cost more disk than
    /// the single PNG the static path writes today.
    func test_sixFrameHeicIsSmallerThanASinglePng() throws {
        let (background, text) = try layers(style: .depth)
        let frames = composer.compose(background: background, text: text,
                                      style: .depth, phases: SolarPhase.allCases)

        let heicURL = tempDir.appendingPathComponent("six.heic")
        try encoder.write(frames: frames, phaseTimes: phaseTimes(), to: heicURL)

        let pngURL = tempDir.appendingPathComponent("one.png")
        let still = try XCTUnwrap(generator.generateWallpaper(
            clipping: clipping, style: .depth, screenSize: size))
        try still.savePNG(to: pngURL)

        let heicBytes = try fileSize(heicURL)
        let pngBytes = try fileSize(pngURL)
        XCTAssertLessThan(heicBytes, pngBytes,
                          "6 kareli HEIC (\(heicBytes) B) tek PNG'den (\(pngBytes) B) küçük olmalı")
    }

    // MARK: - Helpers

    private func fileSize(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    private func averageChannels(_ image: CGImage) -> (red: Double, green: Double, blue: Double) {
        let rep = NSBitmapImageRep(cgImage: image)
        var r = 0.0, g = 0.0, b = 0.0, count = 0.0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 16) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 16) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                r += c.redComponent; g += c.greenComponent; b += c.blueComponent; count += 1
            }
        }
        guard count > 0 else { return (0, 0, 0) }
        return (r / count, g / count, b / count)
    }

    private func averageLuminance(_ image: CGImage) -> Double {
        let rep = NSBitmapImageRep(cgImage: image)
        var total = 0.0
        var count = 0.0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 16) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 16) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }
}
