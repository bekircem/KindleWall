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
        case .allRandom:    return String(localized: "All")
        case .bookByBook:   return String(localized: "Book by Book")
        case .pinnedBooks:  return String(localized: "Pinned")
        case .favorites:    return String(localized: "Favorites")
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
            return String(localized: "Picks at random from every book.")
        case .bookByBook:
            return String(localized: "Moves to another book at random once one book's quotes are exhausted.")
        case .pinnedBooks:
            return String(localized: "Shows quotes only from the books you pinned.")
        case .favorites:
            return String(localized: "Picks at random from the quotes you hearted.")
        }
    }
}
