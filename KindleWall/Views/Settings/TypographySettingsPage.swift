import SwiftUI

/// "Tipografi" page — live type controls (shared with the hero inspector) plus quote decoration.
struct TypographySettingsPage: View {
    let viewModel: MainViewModel
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    private var typographyBinding: Binding<TypographySettings> {
        Binding(
            get: { viewModel.typography },
            set: { viewModel.updateTypography($0) }
        )
    }

    var body: some View {
        SettingsPage(title: "Tipografi") {
            // Decoration
            SettingsCard(title: "Süsleme", footnote: "Alıntının çevresine eklenen dekoratif öğe.") {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(TypographySettings.DecorationStyle.allCases) { style in
                        DecorationStyleChip(
                            style: style,
                            isSelected: settingsVM.decorativeStyle == style
                        ) {
                            settingsVM.updateDecorativeStyle(style)
                            actions.onTypographyChanged()
                        }
                    }
                }
                .padding(Theme.Spacing.l)
            }

            // Live type controls
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    SectionHeader("Yazı Tipi")
                    Spacer()
                    Button("Sıfırla") {
                        viewModel.updateTypography(.default)
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.xs)

                TypographyControls(typography: typographyBinding)
                    .padding(Theme.Spacing.l)
                    .background(
                        Theme.Palette.cardFill,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Theme.Palette.cardStroke, lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - Decoration Style Chip

private struct DecorationStyleChip: View {
    let style: TypographySettings.DecorationStyle
    let isSelected: Bool
    let action: () -> Void

    private var symbol: String {
        switch style {
        case .classicQuote: return "\u{201C}"
        case .minimalDots:  return "⁝"
        case .line:         return "—"
        case .none:         return "∅"
        }
    }

    private var label: String {
        switch style {
        case .classicQuote: return "Tırnak"
        case .minimalDots:  return "Minimal"
        case .line:         return "Çizgi"
        case .none:         return "Yok"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(symbol)
                    .font(.title2)
                    .fontDesign(.serif)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
