import SwiftUI

/// Decoration chips plus the live type controls (shared with the hero inspector) — the
/// "Typography" group of the "Design" page.
struct TypographySection: View {
    let viewModel: MainViewModel

    private var typographyBinding: Binding<TypographySettings> {
        Binding(
            get: { viewModel.typography },
            set: { viewModel.updateTypography($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            // Decoration — reads and writes the same `typography` the sliders below do, so
            // "Reset to Default" can no longer leave the chips highlighting a stale choice.
            SettingsCard(title: String(localized: "Ornament"), footnote: String(localized: "A decorative element placed around the quote.")) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(TypographySettings.DecorationStyle.allCases) { style in
                        DecorationStyleChip(
                            style: style,
                            isSelected: viewModel.typography.decorativeStyle == style
                        ) {
                            viewModel.updateDecorationStyle(style)
                        }
                    }
                }
                .padding(Theme.Spacing.l)
            }

            // Live type controls
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    SectionHeader(String(localized: "Typeface"))
                    Spacer()
                    Button("Reset to Default") {
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
        case .classicQuote: return "Quote Mark"
        case .minimalDots:  return "Minimal"
        case .line:         return "Line"
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
