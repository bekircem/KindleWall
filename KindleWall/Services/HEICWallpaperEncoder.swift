import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Protocol

/// Writes a multi-frame HEIC that macOS treats as a dynamic desktop picture.
protocol HEICWallpaperEncoderProtocol {
    /// Writes `frames` into one HEIC, tagging it so macOS switches frames by time of day.
    /// - Parameters:
    ///   - frames: One image per phase, in the same order as `phaseTimes`.
    ///   - phaseTimes: When each frame becomes current.
    ///   - url: Destination file.
    /// - Throws: `KindleWallError.wallpaperGenerationFailed` if encoding fails.
    func write(frames: [CGImage], phaseTimes: [SolarPhaseTime], to url: URL) throws
}

// MARK: - Implementation

/// Encodes the `apple_desktop:h24` dynamic-wallpaper format.
///
/// The format is undocumented and was confirmed by experiment on macOS 26: an XMP tag in the
/// Apple namespace, attached to the primary image, holding a base64-encoded binary plist. For
/// time-of-day switching the plist is `{ "ti": [ {"i": <frame index>, "t": <fraction of day>} ] }`.
/// A system that ignores the metadata falls back to the primary image, so the wallpaper still
/// works — it just stops changing.
///
/// `solar` (sun altitude/azimuth) and `apr` (light/dark appearance) are the other two variants.
/// `h24` was chosen because the frame times can be pinned to the day's real sunrise and sunset,
/// which keeps the seasons right without depending on Location Services.
final class HEICWallpaperEncoder: HEICWallpaperEncoderProtocol {

    private static let appleNamespace = "http://ns.apple.com/namespace/1.0/"
    private static let appleprefix = "apple_desktop"
    private static let timeKey = "h24"

    func write(frames: [CGImage], phaseTimes: [SolarPhaseTime], to url: URL) throws {
        guard !frames.isEmpty, frames.count == phaseTimes.count else {
            throw KindleWallError.wallpaperGenerationFailed(
                reason: "Kare sayısı faz sayısıyla eşleşmiyor"
            )
        }

        let metadata = try makeMetadata(for: phaseTimes)

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.heic.identifier as CFString, frames.count, nil
        ) else {
            throw KindleWallError.wallpaperGenerationFailed(reason: "HEIC hedefi oluşturulamadı")
        }

        let options = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary

        // The metadata must ride on the primary image; the rest are added plain.
        CGImageDestinationAddImageAndMetadata(destination, frames[0], metadata, options)
        for frame in frames.dropFirst() {
            CGImageDestinationAddImage(destination, frame, options)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw KindleWallError.wallpaperGenerationFailed(reason: "HEIC yazılamadı")
        }
    }

    /// Builds the base64 payload and wraps it in an XMP tag.
    private func makeMetadata(for phaseTimes: [SolarPhaseTime]) throws -> CGImageMetadata {
        let entries = phaseTimes.enumerated().map { index, phaseTime in
            ["i": index, "t": phaseTime.dayFraction()] as [String: Any]
        }

        guard let plist = try? PropertyListSerialization.data(
            fromPropertyList: ["ti": entries], format: .binary, options: 0
        ) else {
            throw KindleWallError.wallpaperGenerationFailed(reason: "Faz verisi kodlanamadı")
        }

        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(
            metadata, Self.appleNamespace as CFString, Self.appleprefix as CFString, nil
        )

        guard let tag = CGImageMetadataTagCreate(
            Self.appleNamespace as CFString,
            Self.appleprefix as CFString,
            Self.timeKey as CFString,
            .string,
            plist.base64EncodedString() as CFString
        ), CGImageMetadataSetTagWithPath(
            metadata, nil, "\(Self.appleprefix):\(Self.timeKey)" as CFString, tag
        ) else {
            throw KindleWallError.wallpaperGenerationFailed(reason: "Dinamik metadata yazılamadı")
        }

        return metadata
    }
}
