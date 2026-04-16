import CryptoKit
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

    /// Generates a deterministic UUID from book title + text content.
    /// The same clipping always produces the same ID across re-imports,
    /// preserving favorites and shown state.
    static func deterministicID(bookTitle: String, text: String) -> UUID {
        let canonical = bookTitle.trimmed.lowercased() + "|||" + text.trimmed.lowercased()
        let digest = SHA256.hash(data: Data(canonical.utf8))
        var bytes = Array(digest.prefix(16))
        // Set UUID version 5 (name-based SHA) bits
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        // Set RFC 4122 variant bits
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
