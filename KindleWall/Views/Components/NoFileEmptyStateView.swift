import SwiftUI

/// Full-panel empty state shown when no Kindle clippings file has been selected.
struct NoFileEmptyStateView: View {
    var onSelectFile: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "book.closed.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Kindle Dosyası Seçilmedi")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("My Clippings.txt dosyanızı seçerek\nKindle alıntılarınızı duvar kağıdına\ndönüştürmeye başlayın.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                onSelectFile()
            } label: {
                Label("Dosya Seç", systemImage: "folder")
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
