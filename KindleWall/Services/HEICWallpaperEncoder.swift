import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Protocol

/// Writes a multi-frame HEIC that macOS treats as a dynamic desktop picture.
/// `Sendable`: HEIC encoding runs on the off-main render path.
protocol HEICWallpaperEncoderProtocol: Sendable {
    /// Writes one HEIC, tagging it so macOS switches frames by time of day.
    ///
    /// Frames arrive one at a time from `nextFrame` and are appended as they come, so only one
    /// full-resolution frame is alive at once. At 3840×2560 the array form held 236 MB.
    ///
    /// - Parameters:
    ///   - phaseTimes: When each frame becomes current; also fixes the frame count.
    ///   - url: Destination file.
    ///   - nextFrame: Produces the frame for the phase at the given index, or nil to abort.
    /// - Throws: `KindleWallError.wallpaperGenerationFailed` if encoding fails.
    func write(phaseTimes: [SolarPhaseTime], to url: URL,
               nextFrame: (Int) -> CGImage?) throws
}

extension HEICWallpaperEncoderProtocol {
    /// Convenience for tests and one-shot callers that already hold every frame.
    func write(frames: [CGImage], phaseTimes: [SolarPhaseTime], to url: URL) throws {
        guard frames.count == phaseTimes.count else {
            throw KindleWallError.wallpaperGenerationFailed(
                reason: String(localized: "The frame count does not match the phase count")
            )
        }
        try write(phaseTimes: phaseTimes, to: url) { frames[$0] }
    }
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

    func write(phaseTimes: [SolarPhaseTime], to url: URL,
               nextFrame: (Int) -> CGImage?) throws {
        guard !phaseTimes.isEmpty else {
            throw KindleWallError.wallpaperGenerationFailed(
                reason: String(localized: "The frame count does not match the phase count")
            )
        }

        let metadata = try makeMetadata(for: phaseTimes)

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.heic.identifier as CFString, phaseTimes.count, nil
        ) else {
            throw KindleWallError.wallpaperGenerationFailed(reason: String(localized: "Could not create the HEIC destination"))
        }

        let options = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary

        try Perf.measure("heic.write", "\(phaseTimes.count) kare") {
            for index in phaseTimes.indices {
                // One frame is produced, appended and released before the next is asked for, so
                // peak memory is one frame rather than all of them.
                guard let frame = nextFrame(index) else {
                    throw KindleWallError.wallpaperGenerationFailed(reason: String(localized: "Could not render a frame"))
                }
                if index == 0 {
                    // The metadata must ride on the primary image; the rest are added plain.
                    CGImageDestinationAddImageAndMetadata(destination, frame, metadata, options)
                } else {
                    CGImageDestinationAddImage(destination, frame, options)
                }
            }

            guard CGImageDestinationFinalize(destination) else {
                throw KindleWallError.wallpaperGenerationFailed(reason: String(localized: "Could not write the HEIC"))
            }
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
            throw KindleWallError.wallpaperGenerationFailed(reason: String(localized: "Could not encode the phase data"))
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
            throw KindleWallError.wallpaperGenerationFailed(reason: String(localized: "Could not write the dynamic metadata"))
        }

        return metadata
    }
}
