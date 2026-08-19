import Foundation

/// Defines how clippings are selected during scheduled wallpaper rotations.
enum RotationMode: String, Codable, CaseIterable, Identifiable {
    /// Fully random across all loaded clippings from all books.
    case allRandom   = "allRandom"
    /// Exhausts all quotes from one book before randomly moving to the next.
    case bookByBook  = "bookByBook"
    /// Only quotes from user-selected (pinned) books are shown.
    case pinnedBooks = "pinnedBooks"
    /// Only quotes the user has favorited (heart-marked) are shown.
    case favorites   = "favorites"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allRandom:    return "Tümü"
        case .bookByBook:   return "Kitap Kitap"
        case .pinnedBooks:  return "Sabitler"
        case .favorites:    return "Favoriler"
        }
    }

    /// Leading glyph for the mode's row.
    var icon: String {
        switch self {
        case .allRandom:    return "shuffle"
        case .bookByBook:   return "book.closed.fill"
        case .pinnedBooks:  return "pin.fill"
        case .favorites:    return "heart.fill"
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
        case .favorites:
            return "Yalnızca kalp ile favorilediğiniz alıntılar arasından rastgele seçer."
        }
    }
}
