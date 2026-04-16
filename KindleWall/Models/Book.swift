import Foundation

/// Represents a book grouped from Kindle clippings sharing the same title.
struct Book: Identifiable, Hashable {
    /// Original title as parsed from My Clippings.txt — used as the unique key.
    let title: String
    /// Original author as parsed from My Clippings.txt.
    let author: String?
    let clippings: [Clipping]

    /// Display title — user override if set, otherwise same as `title`.
    var displayTitle: String
    /// Display author — user override if set, otherwise same as `author`.
    var displayAuthor: String?

    init(title: String, author: String?, clippings: [Clipping],
         displayTitle: String? = nil, displayAuthor: String? = nil) {
        self.title = title
        self.author = author
        self.clippings = clippings
        self.displayTitle = displayTitle ?? title
        self.displayAuthor = displayAuthor ?? author
    }

    var id: String { title }
    var clippingCount: Int { clippings.count }
    var earliestDate: Date? { clippings.compactMap(\.dateAdded).min() }
    var latestDate: Date? { clippings.compactMap(\.dateAdded).max() }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Book, rhs: Book) -> Bool { lhs.id == rhs.id }
}
