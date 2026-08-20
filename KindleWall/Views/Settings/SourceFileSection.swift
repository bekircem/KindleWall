import SwiftUI

/// "Source File" section — choose / reload the Kindle My Clippings.txt source file.
/// A section of the consolidated `BehaviorSettingsPage`.
struct SourceFileSection: View {
    @Bindable var settingsVM: SettingsViewModel
    let clippingsCount: Int
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            SettingsCard(
                footnote: "The My Clippings.txt file from your Kindle. Choosing an updated copy of the same file adds only the new quotes; favorites and shown state are kept."
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
                                    Text("\(clippingsCount) quotes imported")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("No file chosen yet")
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
                            Label("Choose File…", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
    }
}
