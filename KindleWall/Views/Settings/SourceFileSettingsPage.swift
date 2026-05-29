import SwiftUI

/// "Kaynak Dosya" page — choose / reload the Kindle My Clippings.txt source file.
struct SourceFileSettingsPage: View {
    @Bindable var settingsVM: SettingsViewModel
    let clippingsCount: Int
    let actions: SettingsActions

    var body: some View {
        SettingsPage(title: "Kaynak Dosya") {
            SettingsCard(
                title: "My Clippings.txt",
                footnote: "Kindle'ından aldığın My Clippings.txt dosyası. Aynı dosyanın güncel hâlini tekrar seçersen yalnızca yeni alıntılar eklenir; favori ve gösterim durumları korunur."
            ) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.m) {
                        IconTile(symbol: "doc.text.fill", color: Color(.systemGray))

                        VStack(alignment: .leading, spacing: 2) {
                            if let path = settingsVM.clippingsFilePath {
                                Text(path)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if clippingsCount > 0 {
                                    Text("\(clippingsCount) alıntı yüklendi")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Henüz dosya seçilmedi")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }

                    HStack {
                        Spacer()
                        Button {
                            if let url = settingsVM.selectClippingsFile() {
                                actions.onFileSelected(url)
                            }
                        } label: {
                            Label("Dosya Seç…", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
    }
}
