import SwiftUI

/// Full-panel empty state for "there is nothing to show yet".
///
/// Takes its wording from the caller because two very different situations reach it: no file
/// has ever been chosen, or a file was chosen and yielded nothing. Both used to show the same
/// "Kindle Dosyası Seçilmedi" screen, which told the second user something plainly untrue and
/// gave them no idea what had gone wrong.
struct NoFileEmptyStateView: View {
    var symbol: String = "book.closed.fill"
    var title: String = "Kindle Dosyası Seçilmedi"
    var message: String = "My Clippings.txt dosyanızı seçerek\nKindle alıntılarınızı duvar kağıdına\ndönüştürmeye başlayın."
    var actionTitle: String = "Dosya Seç…"
    var onSelectFile: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                onSelectFile()
            } label: {
                Label(actionTitle, systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
