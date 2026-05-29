import SwiftUI

/// A single settings row: leading icon tile, title (+ optional subtitle), and a trailing control.
///
/// Mirrors Loop's row language. Trailing content is a `@ViewBuilder` so callers drop in a
/// `Toggle`, `Picker`, value label, chevron, etc. A convenience init covers display-only rows.
struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            IconTile(symbol: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Theme.Spacing.m)

            trailing
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s + 2)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Display-only row (no trailing control).
extension SettingsRow where Trailing == EmptyView {
    init(icon: String, iconColor: Color, title: String, subtitle: String? = nil) {
        self.init(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}
