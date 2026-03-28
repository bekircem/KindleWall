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
            return "Dosya bulunamadı: \(path)"
        case .fileReadFailed(let error):
            return "Dosya okunamadı: \(error.localizedDescription)"
        case .parsingFailed(let reason):
            return "Dosya ayrıştırılamadı: \(reason)"
        case .wallpaperGenerationFailed(let reason):
            return "Duvar kağıdı oluşturulamadı: \(reason)"
        case .wallpaperApplyFailed(let error):
            return "Duvar kağıdı uygulanamadı: \(error.localizedDescription)"
        case .screenNotAvailable:
            return "Ekran bilgisi alınamadı"
        case .bookmarkCreationFailed:
            return "Dosya yer imi oluşturulamadı"
        case .bookmarkResolutionFailed:
            return "Dosya yer imi çözümlenemedi"
        case .bookmarkStale:
            return "Dosya yer imi geçersiz, lütfen dosyayı yeniden seçin"
        case .noClippingsLoaded:
            return "Henüz alıntı yüklenmedi"
        case .noClippingsAvailable:
            return "Gösterilecek alıntı kalmadı"
        case .directoryCreationFailed(let error):
            return "Klasör oluşturulamadı: \(error.localizedDescription)"
        }
    }
}
