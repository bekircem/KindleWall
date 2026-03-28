import Foundation

/// Available wallpaper visual styles for rendering clippings.
enum WallpaperStyle: String, Codable, CaseIterable, Identifiable {
    case minimalDark = "Minimal Dark"
    case minimalLight = "Minimal Light"
    case gradientWarm = "Gradient Warm"
    case gradientCool = "Gradient Cool"
    case paperTexture = "Paper Texture"
    case elegantSerif = "Elegant Serif"
    case modernSans = "Modern Sans"
    case natureBlur = "Nature Blur"

    var id: String { rawValue }

    /// Display name for the UI (Turkish).
    var displayName: String {
        switch self {
        case .minimalDark: return "Minimal Koyu"
        case .minimalLight: return "Minimal Açık"
        case .gradientWarm: return "Sıcak Gradient"
        case .gradientCool: return "Soğuk Gradient"
        case .paperTexture: return "Kağıt Dokusu"
        case .elegantSerif: return "Zarif Serif"
        case .modernSans: return "Modern Sans"
        case .natureBlur: return "Doğa Bulanık"
        }
    }

    /// Brief description for the style picker.
    var styleDescription: String {
        switch self {
        case .minimalDark: return "Koyu arka plan, beyaz serif tipografi"
        case .minimalLight: return "Kırık beyaz arka plan, koyu tipografi"
        case .gradientWarm: return "Sıcak tonlarda gradient, beyaz metin"
        case .gradientCool: return "Soğuk tonlarda gradient, beyaz metin"
        case .paperTexture: return "Eski kağıt hissi, serif font"
        case .elegantSerif: return "Klasik tipografi, büyük tırnak işaretleri"
        case .modernSans: return "SF Pro, bold başlık stili"
        case .natureBlur: return "Doğa fotoğrafı üzerine blur + metin"
        }
    }
}
