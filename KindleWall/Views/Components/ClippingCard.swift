import SwiftUI

/// A card component displaying a single clipping's text and metadata.
/// Used in BookDetailView.
struct ClippingCard: View {
    let clipping: Clipping
    var isFavorite: Bool = false

    private var metadataLabel: String? {
        var parts: [String] = []
        if let date = clipping.dateAdded {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        switch (clipping.page, clipping.location) {
        case let (p?, l?): parts.append("Sayfa \(p) · Konum \(l)")
        case let (p?, nil): parts.append("Sayfa \(p)")
        case let (nil, l?): parts.append("Konum \(l)")
        default: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(clipping.text)
                    .font(.body)
                    .lineLimit(3)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(clipping.bookTitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let author = clipping.author {
                            Text("— \(author)")
                                .font(.caption)
                                .italic()
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .layoutPriority(0)

                    Spacer(minLength: 8)

                    if let meta = metadataLabel {
                        Text(meta)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .layoutPriority(1)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            if isFavorite {
                Image(systemName: Constants.Icons.favoriteFilled)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
