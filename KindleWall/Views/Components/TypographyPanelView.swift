import SwiftUI

/// Side panel with sliders for adjusting wallpaper typography (the hero preview inspector).
struct TypographyPanelView: View {
    @Binding var typography: TypographySettings
    var onReset: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Tipografi")
                        .font(.headline)
                    Spacer()
                    Button("Sıfırla") {
                        onReset()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                TypographyControls(typography: $typography)

                Spacer()
            }
            .padding()
        }
        .background(.background)
    }
}

/// Reusable typography control stack (basic sliders + advanced disclosure) without panel chrome.
/// Shared by the hero inspector (`TypographyPanelView`) and the "Tipografi" settings page.
struct TypographyControls: View {
    @Binding var typography: TypographySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // MARK: Temel Ayarlar
            VStack(alignment: .leading, spacing: 16) {
                SliderRow(
                    title: "Yazı Boyutu",
                    icon: "textformat.size",
                    value: $typography.fontScale,
                    range: 0.6...1.6,
                    defaultValue: 1.0
                )

                SliderRow(
                    title: "Dikey Konum",
                    icon: "arrow.up.arrow.down",
                    value: $typography.verticalPosition,
                    range: -0.8...0.8,
                    defaultValue: 0.0
                )

                SliderRow(
                    title: "Kenar Boşluğu",
                    icon: "arrow.left.and.right",
                    value: $typography.paddingScale,
                    range: 0.5...1.8,
                    defaultValue: 1.0
                )

                SliderRow(
                    title: "Satır Aralığı",
                    icon: "line.3.horizontal",
                    value: $typography.lineSpacingScale,
                    range: 0.6...1.6,
                    defaultValue: 1.0
                )
            }

            // MARK: Gelişmiş Ayarlar
            DisclosureGroup("Gelişmiş Ayarlar") {
                VStack(alignment: .leading, spacing: 16) {

                    // Font ailesi
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Font Ailesi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(TypographySettings.FontFamily.allCases) { family in
                                FontFamilyChip(
                                    family: family,
                                    isSelected: typography.fontFamily == family
                                ) {
                                    typography.fontFamily = family
                                }
                            }
                        }
                    }
                    .padding(.top, 8)

                    // Metin gölgesi
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $typography.shadowEnabled) {
                            Label("Metin Gölgesi", systemImage: "shadow")
                                .font(.caption)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        if typography.shadowEnabled {
                            SliderRow(
                                title: "Gölge Şiddeti",
                                icon: "circle.lefthalf.filled",
                                value: $typography.shadowRadius,
                                range: 1...20,
                                defaultValue: 4.0,
                                valueFormatter: { String(format: "%.0fpt", $0) }
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(Theme.Motion.smooth, value: typography.shadowEnabled)

                    // Harf aralığı
                    SliderRow(
                        title: "Harf Aralığı",
                        icon: "character.cursor.ibeam",
                        value: $typography.letterSpacing,
                        range: -2...8,
                        defaultValue: 0.0,
                        valueFormatter: {
                            $0 == 0 ? "0pt" : String(format: "%+.1fpt", $0)
                        }
                    )

                    // Metin opaklığı
                    SliderRow(
                        title: "Metin Opaklığı",
                        icon: "circle.dotted",
                        value: $typography.textOpacity,
                        range: 0.3...1.0,
                        defaultValue: 1.0
                    )
                }
            }
            .font(.caption)
        }
    }
}

// MARK: - Font Family Chip

private struct FontFamilyChip: View {
    let family: TypographySettings.FontFamily
    let isSelected: Bool
    let action: () -> Void

    private var sampleFont: Font {
        switch family {
        case .serif:     return .system(size: 16, design: .serif)
        case .sansSerif: return .system(size: 16, design: .default)
        case .classic:   return .custom("Palatino-Roman", size: 16)
        case .monospace: return .system(size: 16, design: .monospaced)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(sampleFont)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Text(family.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(family.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Slider Row

/// A labeled slider row for typography settings.
struct SliderRow: View {
    let title: String
    let icon: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    var valueFormatter: (Double) -> String = { String(format: "%.0f%%", $0 * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(title)
                    .font(.caption)
                Spacer()
                Text(valueFormatter(value))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
                .onDoubleClick {
                    value = defaultValue
                }
        }
    }
}

// MARK: - Double Click Modifier

extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        self.onTapGesture(count: 2, perform: action)
    }
}
