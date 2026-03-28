import Foundation

/// Represents a single clipping entry parsed from Kindle's My Clippings.txt file.
struct Clipping: Identifiable, Codable, Hashable {
    let id: UUID
    let bookTitle: String
    let author: String?
    let text: String
    let page: String?
    let location: String?
    let dateAdded: Date?
    let type: ClippingType

    init(
        id: UUID = UUID(),
        bookTitle: String,
        author: String? = nil,
        text: String,
        page: String? = nil,
        location: String? = nil,
        dateAdded: Date? = nil,
        type: ClippingType = .highlight
    ) {
        self.id = id
        self.bookTitle = bookTitle
        self.author = author
        self.text = text
        self.page = page
        self.location = location
        self.dateAdded = dateAdded
        self.type = type
    }
}
