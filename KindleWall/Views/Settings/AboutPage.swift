import SwiftUI

/// "About" page — app identity and version.
struct AboutPage: View {
    var body: some View {
        SettingsPage(title: "About") {
            SettingsCard {
                VStack(spacing: Theme.Spacing.m) {
                    IconTile(symbol: "text.quote", color: .indigo, size: 56)

                    VStack(spacing: 2) {
                        Text(Constants.App.name)
                            .font(.title2.weight(.bold))
                        Text("Version \(Constants.App.version)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Text("Turns your Kindle highlights into desktop wallpapers.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
            }

            SettingsCard {
                VStack(spacing: Theme.Spacing.m) {
                    Button("Check for Updates") {
                        UpdaterManager.shared.checkForUpdates()
                    }
                    .buttonStyle(.glass)
                    .disabled(!UpdaterManager.shared.canCheckForUpdates)

                    Toggle("Check for updates automatically", isOn: Binding(
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
