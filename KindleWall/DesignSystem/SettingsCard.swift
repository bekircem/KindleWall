import SwiftUI

/// A grouped, rounded container for settings rows on the dark canvas.
///
/// Reserves Liquid Glass for chrome — content cards use a solid elevated surface so dense
/// text stays legible (glass-on-text reduces contrast). Optional `title` renders an uppercased
/// section header above the card; `footnote` renders explanatory text below it.
struct SettingsCard<Content: View>: View {
    /// `String`, not `LocalizedStringKey`, unlike `SettingsPage` and `SettingsRow`: this card
    /// *uppercases* its title, and a key cannot be manipulated. Callers therefore localize the
    /// literal themselves with `String(localized:)` — the casing has to happen on resolved
    /// text, in the right locale, or Turkish loses its dotted capital İ.
    var title: String? = nil
    /// Also `String`: roughly a third of the call sites pass runtime text — a login-item
    /// error, a computed summary — which a key lookup would silently pass through untranslated.
    var footnote: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let title {
                Text(title.uppercasedTurkish)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, Theme.Spacing.xs)
            }

            VStack(spacing: 0) {
                content
            }
            // Fill the column so every card is the same width regardless of its content's
            // intrinsic size (a segmented picker / toggle would otherwise shrink the card).
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.Palette.cardFill,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.cardStroke, lineWidth: 1)
            )

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Uppercased section header that matches `SettingsCard`'s own title treatment.
///
/// For content that lives outside a card (a grid, a custom control) but still needs the
/// same header rhythm as carded sections. The string is uppercased here, so callers pass
/// normal-case text.
struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercasedTurkish)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, Theme.Spacing.xs)
    }
}

/// Inset hairline divider between rows inside a `SettingsCard`, aligned past the icon tile.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Palette.rowDivider)
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.l + Theme.tileSize + Theme.Spacing.m)
    }
}

#Preview {
    SettingsCard(title: "Zamanlama", footnote: "Duvar kağıdının ne sıklıkla değişeceğini seçin.") {
        SettingsRow(icon: "clock.fill", iconColor: .blue, title: "Değişim Sıklığı") {
            Text("1 saat").foregroundStyle(.secondary)
        }
        RowDivider()
        SettingsRow(icon: "shuffle", iconColor: .green, title: "Döngü Modu",
                    subtitle: "Rastgele alıntı seçer") {
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
        }
    }
    .padding(24)
    .frame(width: 420)
    .preferredColorScheme(.dark)
}
