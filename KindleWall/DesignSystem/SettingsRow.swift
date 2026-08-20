import SwiftUI

/// A single settings row: leading icon tile, title (+ optional subtitle), and a trailing control.
///
/// Mirrors Loop's row language. Trailing content is a `@ViewBuilder` so callers drop in a
/// `Toggle`, `Picker`, value label, chevron, etc. A convenience init covers display-only rows.
///
/// Text comes in two flavours. `title`/`subtitle` are `LocalizedStringKey`, so a literal at the
/// call site goes through the String Catalog with no wrapping. `verbatimTitle`/`verbatimSubtitle`
/// take a plain `String` for text that is *data* — a book title, a file name, an error the
/// system produced. Passing such a value as a `LocalizedStringKey` would look it up as a key,
/// miss, and render the raw value: correct-looking in English and still English in Turkish.
struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    /// Defaulted so a caller using the verbatim path need not pass an unused key.
    var title: LocalizedStringKey = ""
    var subtitle: LocalizedStringKey? = nil
    var verbatimTitle: String? = nil
    var verbatimSubtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            IconTile(symbol: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 1) {
                titleText
                    .font(.body)
                    // Let a long title wrap instead of reporting one wide line as its minimum;
                    // otherwise a single row can widen the whole detail column.
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitleText {
                    subtitleText
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

    /// `Text(String)` is verbatim; `Text(LocalizedStringKey)` is looked up. Choosing between
    /// them here keeps every call site from having to know the difference.
    private var titleText: Text {
        if let verbatimTitle { Text(verbatimTitle) } else { Text(title) }
    }

    private var subtitleText: Text? {
        if let verbatimSubtitle { return Text(verbatimSubtitle) }
        if let subtitle { return Text(subtitle) }
        return nil
    }
}

/// Display-only row (no trailing control).
extension SettingsRow where Trailing == EmptyView {
    init(icon: String, iconColor: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.init(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }

    /// Display-only row whose text is data rather than UI copy.
    init(icon: String, iconColor: Color, verbatimTitle: String, verbatimSubtitle: String? = nil) {
        self.init(
            icon: icon, iconColor: iconColor, title: "",
            verbatimTitle: verbatimTitle, verbatimSubtitle: verbatimSubtitle
        ) {
            EmptyView()
        }
    }
}
