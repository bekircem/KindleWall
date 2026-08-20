import SwiftUI

/// "Source File" section — choose / reload the Kindle My Clippings.txt source file.
/// A section of the consolidated `BehaviorSettingsPage`.
struct SourceFileSection: View {
    @Bindable var settingsVM: SettingsViewModel
    let clippingsCount: Int
    let actions: SettingsActions
    /// Disables the check while one is already running, and when there is no file to re-read.
    var canCheckForNewClippings: Bool = false
    var isImporting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            SettingsCard(
                footnote: String(localized: "The My Clippings.txt file from your Kindle. Your Kindle appends to it as you read, so check for new highlights whenever you have been reading — only the new ones are added, and favorites and shown state are kept.")
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

                    HStack(spacing: Theme.Spacing.s) {
                        Spacer()

                        Button {
                            if let url = settingsVM.selectClippingsFile() {
                                actions.onFileSelected(url)
                            }
                        } label: {
                            Label("Choose File…", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)

                        // The bookmark already points at the file; re-reading it should not
                        // cost the user a trip through the open panel every time they read.
                        Button {
                            actions.onCheckForNewClippings()
                        } label: {
                            Label("Check for New Highlights", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canCheckForNewClippings || isImporting)
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
    }
}
