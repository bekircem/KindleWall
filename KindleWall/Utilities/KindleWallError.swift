import Foundation

/// Centralized error type for the KindleWall application.
enum KindleWallError: LocalizedError {
    // Parser errors
    case fileNotFound(path: String)
    case fileReadFailed(underlying: Error)
    case parsingFailed(reason: String)

    // Wallpaper errors
    case wallpaperGenerationFailed(reason: String)
    case wallpaperApplyFailed(underlying: Error)
    case screenNotAvailable

    // Storage errors
    case bookmarkCreationFailed
    case bookmarkResolutionFailed
    case bookmarkStale

    // General errors
    case noClippingsLoaded
    case noClippingsAvailable
    case directoryCreationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return String(localized: "File not found: \(path)")
        case .fileReadFailed(let error):
            return String(localized: "Could not read the file: \(error.localizedDescription)")
        case .parsingFailed(let reason):
            return String(localized: "Could not parse the file: \(reason)")
        case .wallpaperGenerationFailed(let reason):
            return String(localized: "Could not create the wallpaper: \(reason)")
        case .wallpaperApplyFailed(let error):
            return String(localized: "Could not apply the wallpaper: \(error.localizedDescription)")
        case .screenNotAvailable:
            return String(localized: "Could not read the display information")
        case .bookmarkCreationFailed:
            return String(localized: "Could not create the file bookmark")
        case .bookmarkResolutionFailed:
            return String(localized: "Could not resolve the file bookmark")
        case .bookmarkStale:
            return String(localized: "The file bookmark is stale — please choose the file again")
        case .noClippingsLoaded:
            return String(localized: "No quotes loaded yet")
        case .noClippingsAvailable:
            return String(localized: "No quotes left to show")
        case .directoryCreationFailed(let error):
            return String(localized: "Could not create the folder: \(error.localizedDescription)")
        }
    }
}
