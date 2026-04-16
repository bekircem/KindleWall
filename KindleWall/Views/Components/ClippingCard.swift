import SwiftUI

/// A card component displaying a single clipping's text and metadata.
/// Used in BookDetailView.
struct ClippingCard: View {
    let clipping: Clipping
    var isFavorite: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(clipping.text)
                    .font(.body)
                    .lineLimit(3)

                HStack(spacing: 4) {
                    Text(clipping.bookTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)

                    if let author = clipping.author {
                        Text("— \(author)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }

                if let date = clipping.dateAdded {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isFavorite {
                Image(systemName: Constants.Icons.favoriteFilled)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
