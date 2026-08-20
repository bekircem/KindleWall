import SwiftUI

/// First-run setup: what the app does, where the quotes come from, how it looks, how often it
/// changes.
///
/// Drives the real `MainViewModel` rather than keeping a parallel parser, generator and
/// `WallpaperManager` of its own. That duplication is what made the old flow render previews
/// with `typography: .default` — ignoring the dynamic-wallpaper, long-quote and style
/// typography settings — and swallow apply failures with `try?`, so the wallpaper the user
/// approved during setup was not the one they got afterwards.
struct OnboardingView: View {
    @Bindable var viewModel: MainViewModel
    @Bindable var settingsVM: SettingsViewModel
    var onComplete: () -> Void

    @State private var step: Step = .welcome
    /// Drives the slide direction (forward = next slides in from the trailing edge).
    @State private var slideForward = true
    @State private var sourceError: String?
    @State private var isDropTargeted = false

    private enum Step: Int, CaseIterable, Comparable {
        case welcome, source, design, rhythm, done

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Whether there is anything to render — the gate for moving past the source step.
    private var hasQuotes: Bool { !viewModel.clippings.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcomeStep
                case .source:  sourceStep
                case .design:  designStep
                case .rhythm:  rhythmStep
                case .done:    doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
                removal:   .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)
            ))
            .id(step)

            navigationBar
        }
        .frame(width: 700, height: 600)
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            if step > .welcome {
                Button("Back", action: goBack)
                    .keyboardShortcut("[", modifiers: .command)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Circle()
                        .fill(s == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityHidden(true)

            Spacer()

            if step == .done {
                Button("Finish", action: finish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Next", action: goNext)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    // Only the source step can block, and only until there is something to
                    // show. There is always a way forward from it — a file, the samples, or
                    // "sonra".
                    .disabled(step == .source && !hasQuotes)
            }
        }
        .padding()
    }

    private func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        slideForward = true
        withAnimation(Theme.Motion.smooth) { step = next }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        slideForward = false
        withAnimation(Theme.Motion.smooth) { step = previous }
    }

    /// Finishing applies through the normal path, so what lands on the desktop is exactly what
    /// the design step previewed.
    private func finish() {
        if viewModel.currentClipping == nil { viewModel.selectRandomClipping() }
        viewModel.applyWallpaper()
        viewModel.startScheduler()
        onComplete()
    }

    // MARK: - Step 1 · Welcome

    private var welcomeStep: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            IconTile(symbol: "quote.bubble.fill", color: .indigo, size: 76)

            Text("Welcome to KindleWall")
                .font(.largeTitle.weight(.bold))

            Text("The lines you highlighted on your Kindle become your desktop wallpaper, changing on the schedule you set.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)

            Spacer()
        }
        .padding()
    }

    // MARK: - Step 2 · Source

    private var sourceStep: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            stepTitle("Alıntıların Nereden Gelsin?",
                      subtitle: "Kindle'ını bağlayıp My Clippings.txt dosyasını seç — ya da şimdilik örneklerle başla.")

            dropZone

            // The error belongs on the step that produced it. It used to be set here and drawn
            // on the *previous* screen, so a parse failure appeared somewhere the user had
            // already left.
            if let sourceError {
                Label(sourceError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 40)
            }

            if viewModel.importState.isRunning {
                ProgressView(value: viewModel.importState.progress)
                    .frame(width: 240)
            } else if hasQuotes {
                Label("\(viewModel.clippings.count) alıntı hazır", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            HStack(spacing: Theme.Spacing.m) {
                Button {
                    chooseFile()
                } label: {
                    Label("Choose File…", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button("No Kindle — Try the Samples") {
                    sourceError = nil
                    viewModel.loadSampleClippings()
                }
                .buttonStyle(.bordered)
            }

            Button("I'll do it later") {
                viewModel.loadSampleClippings()
                goNext()
            }
            .buttonStyle(.link)
            .font(.caption)

            Spacer()
        }
        .padding()
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.hero)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
            .frame(height: 130)
            .overlay {
                VStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                    Text(settingsVM.clippingsFilePath.map { ($0 as NSString).lastPathComponent }
                         ?? "Dosyayı buraya sürükleyin")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { load(url) }
                }
                return true
            }
            .padding(.horizontal, 40)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "My Clippings.txt Dosyasını Seçin"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func load(_ url: URL) {
        sourceError = nil
        settingsVM.clippingsFilePath = url.path
        viewModel.loadClippings(from: url)
    }

    // MARK: - Step 3 · Design

    private var designStep: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                stepTitle("Nasıl Görünsün?",
                          subtitle: "Her stil kendi yazı tipi ve süslemesiyle gelir. Önizleme kendi alıntınla çizilir.")

                // The real preview from the real pipeline — same renderer, same settings.
                WallpaperPreviewView(image: viewModel.currentWallpaperImage, cornerRadius: Theme.Radius.card)
                    .frame(maxHeight: 190)
                    .padding(.horizontal, 40)

                if let clipping = viewModel.currentClipping {
                    Text("\"\(clipping.text.truncated(to: 90))\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 40)
                }

                Button {
                    viewModel.selectRandomClipping()
                } label: {
                    Label("New Quote", systemImage: Constants.Icons.newQuote)
                }
                .disabled(!hasQuotes)

                StylePickerView(selectedStyle: Binding(
                    get: { viewModel.selectedStyle },
                    set: { viewModel.updateStyle($0) }
                ))
                .padding(.horizontal)
            }
            .padding()
        }
        .onAppear {
            // Guarantees something to look at even if the user arrived without touching a
            // control. The old flow relied on an onChange that never fired for the default style.
            if viewModel.currentClipping == nil { viewModel.selectRandomClipping() }
            if viewModel.currentWallpaperImage == nil { viewModel.generatePreview() }
        }
    }

    // MARK: - Step 4 · Rhythm & permissions

    private var rhythmStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                stepTitle("Ne Sıklıkla Değişsin?", subtitle: nil)
                    .frame(maxWidth: .infinity)

                SettingsCard(footnote: "Alıntı bu aralıkla değişir. Görünüm ayarların anında uygulanır.") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Picker("Change Interval", selection: Binding(
                            get: { settingsVM.scheduleInterval },
                            set: {
                                settingsVM.updateSchedule($0)
                                viewModel.updateScheduleInterval($0, customDate: settingsVM.customScheduleDate)
                            }
                        )) {
                            ForEach(ScheduleInterval.allCases) { interval in
                                Text(interval.rawValue).tag(interval)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(Theme.Spacing.l)
                }

                SettingsCard(title: "Tercihler") {
                    SettingsRow(icon: "menubar.rectangle", iconColor: .indigo,
                                title: "Show in Menu Bar",
                                subtitle: "Change the quote without opening the window") {
                        Toggle("", isOn: $settingsVM.showInMenuBar).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow(icon: "power", iconColor: .green, title: "Open at Login") {
                        Toggle("", isOn: $settingsVM.launchAtLogin).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow(icon: "bell.fill", iconColor: .red, title: "Send Notifications") {
                        Toggle("", isOn: $settingsVM.showNotifications).labelsHidden()
                    }
                }
                .onChange(of: [settingsVM.showInMenuBar, settingsVM.launchAtLogin,
                               settingsVM.showNotifications]) {
                    settingsVM.saveSettings()
                }
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Step 5 · Done

    private var doneStep: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            IconTile(symbol: "checkmark.circle.fill", color: .green, size: 68)

            Text("You're Ready")
                .font(.largeTitle.weight(.bold))

            // The one thing the app most needs to teach: design edits land on the desktop by
            // themselves. Without saying it, people hunt for a save button that isn't there.
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                tourRow(icon: "paintpalette.fill", color: .purple, title: "Design",
                        detail: "Stil, arka plan ve tipografi tek sayfada. Değişiklikler masaüstüne kendiliğinden uygulanır.")
                tourRow(icon: "text.quote", color: .indigo, title: "Menü çubuğu",
                        detail: "Pencere kapalıyken bile alıntıyı değiştirebilir, duraklatabilirsin.")
                tourRow(icon: "books.vertical.fill", color: .orange, title: "Kütüphane",
                        detail: "Tüm alıntıların; favorile, düzenle, doğrudan duvar kağıdı yap.")
            }
            .padding(.horizontal, 60)

            Spacer()
        }
        .padding()
    }

    private func tourRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            IconTile(symbol: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared

    private func stepTitle(_ title: String, subtitle: String?) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(title)
                .font(.title.weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}
