import SwiftUI

/// A styled view for displaying a quote with decorative quotation marks.
struct QuoteView: View {
    let text: String
    let bookTitle: String
    let author: String?

    var body: some View {
        VStack(spacing: 12) {
            // Opening decorative quote
            Text("\u{201C}")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundStyle(.secondary.opacity(0.3))

            // Quote text
            Text(text)
                .font(.system(.body, design: .serif))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Closing decorative quote
            Text("\u{201D}")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundStyle(.secondary.opacity(0.3))

            // Attribution
            HStack(spacing: 4) {
                Text(bookTitle)
                    .fontWeight(.medium)
                if let author {
                    Text("— \(author)")
                        .italic()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
