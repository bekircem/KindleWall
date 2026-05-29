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
                RoundedRectangle(cornerRadius: 8)
                    .fill(previewGradient)

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

    private var previewGradient: LinearGradient {
        switch style {
        case .minimalDark:
            return LinearGradient(colors: [Color(nsColor: .darkGray), .black], startPoint: .top, endPoint: .bottom)
        case .minimalLight:
            return LinearGradient(colors: [Color(white: 0.96), Color(white: 0.92)], startPoint: .top, endPoint: .bottom)
        case .gradientWarm:
            return LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gradientCool:
            return LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .paperTexture:
            return LinearGradient(colors: [Color(red: 0.96, green: 0.91, blue: 0.76)], startPoint: .top, endPoint: .bottom)
        case .elegantSerif:
            return LinearGradient(colors: [Color(white: 0.17), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
        case .modernSans:
            return LinearGradient(colors: [Color(white: 0.05), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
        case .natureBlur:
            return LinearGradient(colors: [.green.opacity(0.6), .green.opacity(0.3)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var previewFontDesign: Font.Design {
        switch style {
        case .elegantSerif, .paperTexture:
            return .serif
        case .modernSans, .minimalDark, .minimalLight,
             .gradientWarm, .gradientCool, .natureBlur:
            return .default
        }
    }

    private var previewTextColor: Color {
        switch style {
        case .minimalLight, .paperTexture:
            return .black.opacity(0.7)
        default:
            return .white.opacity(0.8)
        }
    }
}
