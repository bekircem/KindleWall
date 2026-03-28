import SwiftUI

/// Displays a wallpaper image preview with aspect ratio and styling.
struct WallpaperPreviewView: View {
    let image: NSImage?
    var cornerRadius: CGFloat = 12

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.quaternary)
                .aspectRatio(16/10, contentMode: .fit)
                .overlay {
                    Image(systemName: Constants.Icons.wallpaper)
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
        }
    }
}
