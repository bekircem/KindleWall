import SwiftUI

/// A rounded-rectangle icon tile with a gradient fill and a white glyph.
///
/// The Loop-style colored icon used in both the sidebar and settings rows.
/// Extracted into one component so the sidebar and content share identical icon treatment.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = Theme.tileSize

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                color.gradient,
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
    }
}

#Preview {
    HStack(spacing: 12) {
        IconTile(symbol: "quote.bubble.fill", color: .indigo)
        IconTile(symbol: "books.vertical.fill", color: .orange)
        IconTile(symbol: "clock.fill", color: .blue)
        IconTile(symbol: "textformat", color: .pink)
    }
    .padding()
    .preferredColorScheme(.dark)
}
