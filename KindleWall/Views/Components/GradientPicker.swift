import SwiftUI

/// A gradient color picker for customizing wallpaper backgrounds.
/// Prepared for future custom color support.
struct GradientPicker: View {
    @Binding var startColor: Color
    @Binding var endColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Preview
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [startColor, endColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 60)

            HStack {
                VStack(alignment: .leading) {
                    Text("Başlangıç")
                        .font(.caption)
                    ColorPicker("", selection: $startColor)
                        .labelsHidden()
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("Bitiş")
                        .font(.caption)
                    ColorPicker("", selection: $endColor)
                        .labelsHidden()
                }
            }
        }
    }
}
