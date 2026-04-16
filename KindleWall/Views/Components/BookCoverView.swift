import SwiftUI

/// A book cover thumbnail that shows a real cover image when available,
/// falling back to a deterministic gradient + initials placeholder.
struct BookCoverView: View {
    let bookTitle: String
    let author: String?
    /// Real cover image fetched from API. When nil the gradient placeholder is shown.
    var coverImage: NSImage? = nil
    var width: CGFloat = 48
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let img = coverImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(BookCoverColors.gradient(for: bookTitle))
                    .overlay {
                        Text(BookCoverColors.initials(for: bookTitle))
                            .font(.system(size: max(width * 0.35, 12), weight: .bold, design: .serif))
                            .foregroundColor(.white.opacity(0.9))
                    }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Shared color helpers (used by BookCoverView and ClippingGridCard)

enum BookCoverColors {
    private static let palettes: [(Color, Color)] = [
        (.purple, .indigo),
        (.blue, .cyan),
        (.orange, .red),
        (.teal, .green),
        (.pink, .purple),
        (.brown, .orange),
        (.indigo, .blue),
        (.mint, .teal)
    ]

    static func paletteIndex(for bookTitle: String) -> Int {
        abs(bookTitle.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palettes.count
    }

    static func gradient(for bookTitle: String) -> LinearGradient {
        let (top, bottom) = palettes[paletteIndex(for: bookTitle)]
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func initials(for bookTitle: String) -> String {
        let words = bookTitle.split(separator: " ").prefix(2)
        return words.compactMap { $0.first }.map(String.init).joined()
    }
}
