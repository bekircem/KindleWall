import SwiftUI

/// Content displayed in the menu bar dropdown.
struct MenuBarView: View {
    @Bindable var viewModel: MainViewModel
    var onOpenWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current quote preview
            if let clipping = viewModel.currentClipping {
                Text(clipping.text.truncated(to: 100))
                    .font(.callout)
                    .lineLimit(2)

                Text(clipping.bookTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Alıntı yüklenmedi")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                viewModel.selectRandomClipping()
                viewModel.applyWallpaper()
            } label: {
                Label("Yeni Alıntı", systemImage: Constants.Icons.newQuote)
            }

            Button {
                // TODO: Implement pause/resume toggle
            } label: {
                Label("Durakla", systemImage: Constants.Icons.pause)
            }

            if let nextDate = (viewModel as AnyObject).value(forKey: "nextChangeDate") as? Date {
                let _ = nextDate // Silence unused warning
                Text("Sonraki: —")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                onOpenWindow()
            } label: {
                Label("Pencereyi Aç", systemImage: "macwindow")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Çıkış", systemImage: "xmark.circle")
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
