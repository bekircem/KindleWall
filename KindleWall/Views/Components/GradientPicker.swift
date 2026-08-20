import SwiftUI

/// A gradient color picker for customizing wallpaper backgrounds.
/// Prepared for future custom color support.
struct GradientPicker: View {
    @Binding var startColor: Color
    @Binding var endColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // Preview
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .fill(
                    LinearGradient(
                        colors: [startColor, endColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 60)

            // Tidy label-left / swatch-right rows instead of edge-spread wells.
            LabeledContent("Start") {
                ColorPicker("", selection: $startColor)
                    .labelsHidden()
            }

            LabeledContent("End") {
                ColorPicker("", selection: $endColor)
                    .labelsHidden()
            }
        }
    }
}
