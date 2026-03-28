import SwiftUI

/// Grid view for selecting a wallpaper style with mini previews.
struct StylePickerView: View {
    @Binding var selectedStyle: WallpaperStyle

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(WallpaperStyle.allCases) { style in
                StyleCard(style: style, isSelected: selectedStyle == style)
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.3)) {
                            selectedStyle = style
                        }
                    }
            }
        }
    }
}

// MARK: - Style Card

struct StyleCard: View {
    let style: WallpaperStyle
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Mini preview
            RoundedRectangle(cornerRadius: 8)
                .fill(previewGradient)
                .frame(height: 80)
                .overlay {
                    Text("\u{201C}Aa\u{201D}")
                        .font(.title2)
                        .foregroundColor(previewTextColor)
                }

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
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
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

    private var previewTextColor: Color {
        switch style {
        case .minimalLight, .paperTexture:
            return .black.opacity(0.7)
        default:
            return .white.opacity(0.8)
        }
    }
}
