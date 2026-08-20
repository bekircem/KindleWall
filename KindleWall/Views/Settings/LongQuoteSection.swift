import SwiftUI

/// "Long Quotes" section — skip overly long quotes and/or auto-tighten their typography.
/// A section of the consolidated `BehaviorSettingsPage`.
struct LongQuoteSection: View {
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            // MARK: Skip
            SettingsCard(
                title: "Skip Long Quotes",
                footnote: settingsVM.skipLongQuotesEnabled
                    ? "Quotes longer than this threshold are skipped when choosing a wallpaper."
                    : nil
            ) {
                SettingsRow(icon: "arrow.forward.to.line", iconColor: .orange,
                            title: "Skip long quotes") {
                    Toggle("", isOn: Binding(
                        get: { settingsVM.skipLongQuotesEnabled },
                        set: { newValue in
                            settingsVM.skipLongQuotesEnabled = newValue
                            settingsVM.updateLongQuoteSettings()
                        }
                    ))
                    .labelsHidden()
                }

                if settingsVM.skipLongQuotesEnabled {
                    RowDivider()
                    LabeledContent("Threshold") {
                        ThresholdInput(
                            value: Binding(
                                get: { settingsVM.longQuoteThreshold },
                                set: { newValue in
                                    settingsVM.longQuoteThreshold = newValue
                                    settingsVM.updateLongQuoteSettings()
                                }
                            ),
                            unit: Binding(
                                get: { settingsVM.longQuoteUnit },
                                set: { settingsVM.updateLongQuoteUnit($0) }
                            ),
                            range: settingsVM.longQuoteRange(for: settingsVM.longQuoteUnit),
                            step: settingsVM.longQuoteStep(for: settingsVM.longQuoteUnit)
                        )
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.m)
                }
            }

            // MARK: Tighten
            SettingsCard(
                title: "Tighten Long Quotes",
                footnote: settingsVM.autoTightenLongQuotes
                    ? "Eşikten uzun alıntılar, font boyutu bu değere ve satır arası bu çarpana kadar daraltılır. Çok düşük değerler okunabilirliği azaltabilir."
                    : nil
            ) {
                SettingsRow(icon: "textformat.size.smaller", iconColor: .orange,
                            title: "Tighten long quotes automatically") {
                    Toggle("", isOn: Binding(
                        get: { settingsVM.autoTightenLongQuotes },
                        set: { newValue in
                            settingsVM.autoTightenLongQuotes = newValue
                            settingsVM.updateLongQuoteSettings()
                            actions.onTypographyChanged()
                        }
                    ))
                    .labelsHidden()
                }

                if settingsVM.autoTightenLongQuotes {
                    RowDivider()
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        LabeledContent("From this threshold") {
                            ThresholdInput(
                                value: Binding(
                                    get: { settingsVM.tightenThreshold },
                                    set: { newValue in
                                        settingsVM.tightenThreshold = newValue
                                        settingsVM.updateLongQuoteSettings()
                                        actions.onTypographyChanged()
                                    }
                                ),
                                unit: Binding(
                                    get: { settingsVM.tightenUnit },
                                    set: {
                                        settingsVM.updateTightenUnit($0)
                                        actions.onTypographyChanged()
                                    }
                                ),
                                range: settingsVM.tightenThresholdRange(for: settingsVM.tightenUnit),
                                step: settingsVM.tightenThresholdStep(for: settingsVM.tightenUnit)
                            )
                        }

                        LabeledContent("Minimum text size") {
                            HStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { settingsVM.tightenMinFontPt },
                                        set: { newValue in
                                            settingsVM.tightenMinFontPt = newValue
                                            settingsVM.updateLongQuoteSettings()
                                            actions.onTypographyChanged()
                                        }
                                    ),
                                    in: 10...20,
                                    step: 1
                                )
                                Text("\(Int(settingsVM.tightenMinFontPt)) pt")
                                    .monospacedDigit()
                                    .frame(width: 48, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        LabeledContent("Line spacing") {
                            HStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { settingsVM.tightenLineSpacingMultiplier },
                                        set: { newValue in
                                            settingsVM.tightenLineSpacingMultiplier = newValue
                                            settingsVM.updateLongQuoteSettings()
                                            actions.onTypographyChanged()
                                        }
                                    ),
                                    in: 0.15...0.45,
                                    step: 0.01
                                )
                                Text(String(format: "%.2f×", settingsVM.tightenLineSpacingMultiplier))
                                    .monospacedDigit()
                                    .frame(width: 56, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Reset to Default") {
                                settingsVM.resetLongQuoteTypography()
                                actions.onTypographyChanged()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
            }
        }
    }
}

// MARK: - Threshold Input

/// Free-form numeric TextField + Stepper + unit Picker, shared by the skip and tighten thresholds.
private struct ThresholdInput: View {
    @Binding var value: Int
    @Binding var unit: LengthUnit
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 8) {
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .monospacedDigit()

            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()

            Picker("", selection: $unit) {
                ForEach(LengthUnit.allCases) { u in
                    Text(u.displayName).tag(u)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }
}
