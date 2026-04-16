import Foundation

/// Defines how clippings are selected during scheduled wallpaper rotations.
enum RotationMode: String, Codable, CaseIterable, Identifiable {
    /// Fully random across all loaded clippings from all books.
    case allRandom   = "allRandom"
    /// Exhausts all quotes from one book before randomly moving to the next.
    case bookByBook  = "bookByBook"
    /// Only quotes from user-selected (pinned) books are shown.
    case pinnedBooks = "pinnedBooks"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allRandom:    return "Tümünden Rastgele"
        case .bookByBook:   return "Kitap Kitap"
        case .pinnedBooks:  return "Seçili Kitaplar"
        }
    }

    var modeDescription: String {
        switch self {
        case .allRandom:
            return "Tüm kitaplardaki alıntılar arasından rastgele seçer."
        case .bookByBook:
            return "Bir kitaptaki tüm alıntılar gösterilince rastgele yeni bir kitaba geçer."
        case .pinnedBooks:
            return "Yalnızca sabitlediğiniz kitaplardan alıntı gösterir."
        }
    }
}
