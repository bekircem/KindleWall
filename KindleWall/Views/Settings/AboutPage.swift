import SwiftUI

/// "Hakkında" page — app identity and version.
struct AboutPage: View {
    var body: some View {
        SettingsPage(title: "Hakkında") {
            SettingsCard {
                VStack(spacing: Theme.Spacing.m) {
                    IconTile(symbol: "text.quote", color: .indigo, size: 56)

                    VStack(spacing: 2) {
                        Text(Constants.App.name)
                            .font(.title2.weight(.bold))
                        Text("Sürüm \(Constants.App.version)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Text("Kindle alıntılarını şık duvar kağıtlarına dönüştürür.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
            }

            SettingsCard {
                VStack(spacing: Theme.Spacing.m) {
                    Button("Güncellemeleri Denetle") {
                        UpdaterManager.shared.checkForUpdates()
                    }
                    .buttonStyle(.glass)
                    .disabled(!UpdaterManager.shared.canCheckForUpdates)

                    Toggle("Güncellemeleri otomatik denetle", isOn: Binding(
                        get: { UpdaterManager.shared.automaticallyChecksForUpdates },
                        set: { UpdaterManager.shared.automaticallyChecksForUpdates = $0 }
                    ))
                    .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
            }
        }
    }
}
