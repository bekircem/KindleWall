import SwiftUI

/// Grid view for selecting a wallpaper style with mini previews.
struct StylePickerView: View {
    @Binding var selectedStyle: WallpaperStyle

    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(WallpaperStyle.allCases) { style in
                Button {
                    withAnimation(Theme.Motion.snappy) {
                        selectedStyle = style
                    }
                } label: {
                    StyleCard(style: style, isSelected: selectedStyle == style)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.displayName)
            }
        }
    }
}

// MARK: - Style Card

struct StyleCard: View {
    let style: WallpaperStyle
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            // Mini preview at wallpaper aspect ratio
            ZStack(alignment: .topLeading) {
                previewFill
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 0) {
                    Text("\u{201C}")
                        .font(.system(size: 24, weight: .bold, design: previewFontDesign))
                        .foregroundColor(previewTextColor.opacity(0.4))
                        .padding(.bottom, -4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Okunmak, binlerce")
                        Text("farklı hayat yaşamak")
                        Text("demektir.")
                    }
                    .font(.system(size: 9, weight: .regular, design: previewFontDesign))
                    .foregroundColor(previewTextColor)
                    .lineLimit(1)

                    Spacer()

                    Text("— Yazar Adı")
                        .font(.system(size: 8, weight: .light, design: previewFontDesign))
                        .foregroundColor(previewTextColor.opacity(0.6))
                        .italic()
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .aspectRatio(16/10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(style.displayName)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)

            Text(style.styleDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.hover, value: isHovered)
    }

    private var cardBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.1) }
        if isHovered { return Color(nsColor: .quaternaryLabelColor) }
        return .clear
    }

    /// Card preview fill. Mirrors the real background each style renders, including Forest
    /// Light's radial shaft — a linear gradient there would misrepresent the one style whose
    /// surface is radial.
    @ViewBuilder
    private var previewFill: some View {
        switch style {
        case .night:
            LinearGradient(colors: [Color(white: 0.11), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
        case .paper:
            LinearGradient(colors: [Color(red: 0.96, green: 0.91, blue: 0.76)], startPoint: .top, endPoint: .bottom)
        case .grid:
            LinearGradient(colors: [Color(white: 0.05), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
        case .dawn:
            LinearGradient(colors: [Color(red: 1.0, green: 0.54, blue: 0.30),
                                    Color(red: 0.54, green: 0.18, blue: 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .depth:
            LinearGradient(colors: [Color(red: 0.40, green: 0.49, blue: 0.92),
                                    Color(red: 0.11, green: 0.08, blue: 0.39)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .forestLight:
            RadialGradient(colors: [Color(red: 0.21, green: 0.40, blue: 0.18),
                                    Color(red: 0.03, green: 0.08, blue: 0.04)],
                           center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 90)
        }
    }

    private var previewFontDesign: Font.Design {
        switch style.defaultFontFamily {
        case .serif, .classic: return .serif
        case .monospace:       return .monospaced
        case .sansSerif:       return .default
        }
    }

    private var previewTextColor: Color {
        style.hasLightBackground ? .black.opacity(0.7) : .white.opacity(0.8)
    }
}
