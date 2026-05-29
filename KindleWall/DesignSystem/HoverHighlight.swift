import SwiftUI

/// Adds a subtle, animated background highlight when the pointer is over a view.
///
/// macOS list/menu rows highlight on hover; many of our `.buttonStyle(.plain)` rows and
/// autocomplete results were missing this. Uses the shared `Theme.Palette.hover` fill and
/// `Theme.Motion.hover` timing so the feedback feels identical everywhere.
private struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                isHovered ? Theme.Palette.hover : Color.clear,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .onHover { isHovered = $0 }
            .animation(Theme.Motion.hover, value: isHovered)
    }
}

extension View {
    /// Highlights the view's background on pointer hover (Loop-style row feedback).
    func hoverHighlight(cornerRadius: CGFloat = Theme.Radius.control) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}
