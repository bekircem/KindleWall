import SwiftUI

/// Three-step onboarding flow for first-time users.
struct OnboardingView: View {
    var onComplete: (URL, WallpaperStyle, ScheduleInterval) -> Void

    @State private var currentStep: Int = 0
    /// Drives the slide direction of the step transition (forward = next slides in from trailing).
    @State private var slideForward = true
    @State private var selectedFileURL: URL?
    @State private var selectedStyle: WallpaperStyle = .night
    @State private var selectedInterval: ScheduleInterval = .hourly

    // Preview state
    @State private var parsedClippings: [Clipping] = []
    @State private var sampleClipping: Clipping?
    @State private var previewImage: NSImage?
    @State private var isGenerating: Bool = false
    @State private var parseErrorMessage: String?
    @State private var isDropTargeted: Bool = false

    private let parser = ClippingsParser()
    private let generator = WallpaperGenerator()

    var body: some View {
        VStack(spacing: 0) {
            // Step content — chrome-less custom pager (no OS tab bar)
            Group {
                switch currentStep {
                case 0:  welcomeStep
                case 1:  fileSelectStep
                default: styleStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
                removal:   .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)
            ))
            .id(currentStep)

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Geri", action: goBack)
                        .keyboardShortcut("[", modifiers: .command)
                }

                Spacer()

                // Step indicator
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityHidden(true)

                Spacer()

                if currentStep < 2 {
                    Button("İleri", action: goNext)
                        .disabled(currentStep == 1 && selectedFileURL == nil)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Başla") {
                        if let url = selectedFileURL {
                            onComplete(url, selectedStyle, selectedInterval)
                        }
                    }
                    .disabled(selectedFileURL == nil)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 700, height: 580)
        .onChange(of: selectedStyle) { _, _ in
            generatePreview()
        }
    }

    // MARK: - Navigation

    private func goNext() {
        guard currentStep < 2 else { return }
        slideForward = true
        let next = currentStep + 1
        withAnimation(Theme.Motion.smooth) {
            currentStep = next
        }
        if next == 2 {
            loadClippingsAndPreview()
        }
    }

    private func goBack() {
        guard currentStep > 0 else { return }
        slideForward = false
        withAnimation(Theme.Motion.smooth) {
            currentStep -= 1
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()

            IconTile(symbol: "quote.bubble.fill", color: .indigo, size: 76)

            Text("KindleWall'a Hoş Geldiniz")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Kindle alıntılarınızı masaüstü duvar kağıdına dönüştürün.\nHer gün farklı bir ilham kaynağı.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var fileSelectStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Dosyanızı Seçin")
                .font(.title)
                .fontWeight(.bold)

            Text("Kindle cihazınızdaki My Clippings.txt dosyasını seçin.")
                .foregroundStyle(.secondary)

            // Drop area
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                .frame(height: 150)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)

                        if let url = selectedFileURL {
                            Text(url.lastPathComponent)
                                .font(.headline)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Dosyayı buraya sürükleyin")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                        guard let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        DispatchQueue.main.async {
                            selectedFileURL = url
                            parseErrorMessage = nil
                        }
                    }
                    return true
                }
                .padding(.horizontal, 40)

            if let error = parseErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 40)
            }

            Button("Dosya Seç") {
                let panel = NSOpenPanel()
                panel.title = "My Clippings.txt Dosyasını Seçin"
                panel.allowedContentTypes = [.plainText]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK {
                    selectedFileURL = panel.url
                }
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var styleStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Stil ve Zamanlama")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Varsayılan duvar kağıdı stilinizi ve değişim sıklığını seçin.")
                    .foregroundStyle(.secondary)

                // Wallpaper preview
                Group {
                    if isGenerating {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.quaternary)
                            .aspectRatio(16/10, contentMode: .fit)
                            .overlay { ProgressView() }
                    } else {
                        WallpaperPreviewView(image: previewImage, cornerRadius: 12)
                    }
                }
                .frame(maxHeight: 180)
                .padding(.horizontal, 40)

                // Preview info and actions
                if let clipping = sampleClipping {
                    Text("\"\(clipping.text.truncated(to: 80))\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 40)
                }

                HStack(spacing: 12) {
                    Button {
                        pickRandomClipping()
                        generatePreview()
                    } label: {
                        Label("Farklı Alıntı", systemImage: Constants.Icons.newQuote)
                    }
                    .disabled(parsedClippings.isEmpty)

                    Button {
                        applyPreviewWallpaper()
                    } label: {
                        Label("Wallpaper Uygula", systemImage: Constants.Icons.wallpaper)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(previewImage == nil)
                }

                StylePickerView(selectedStyle: $selectedStyle)
                    .padding(.horizontal)

                Picker("Değişim Sıklığı", selection: $selectedInterval) {
                    ForEach(ScheduleInterval.allCases) { interval in
                        Text(interval.rawValue).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)
            }
            .padding()
        }
    }

    // MARK: - Preview Helpers

    private func loadClippingsAndPreview() {
        guard let url = selectedFileURL else { return }
        guard parsedClippings.isEmpty else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            parsedClippings = try parser.parse(fileURL: url)
            if parsedClippings.isEmpty {
                parseErrorMessage = "Dosyada alıntı bulunamadı. Lütfen geçerli bir My Clippings.txt seçin."
            } else {
                parseErrorMessage = nil
                pickRandomClipping()
                generatePreview()
            }
        } catch {
            parseErrorMessage = (error as? KindleWallError)?.errorDescription ?? "Dosya okunamadı."
        }
    }

    private func pickRandomClipping() {
        sampleClipping = parsedClippings.randomElement()
    }

    private func generatePreview() {
        guard let clipping = sampleClipping else { return }
        guard let screen = NSScreen.main else { return }

        isGenerating = true
        // Use 1x resolution for preview (readable in the small preview area)
        let screenSize = screen.frame.size
        let style = selectedStyle
        let capturedGenerator = generator  // capture before Task.detached to avoid @MainActor isolation warning

        Task.detached {
            let image = capturedGenerator.generateWallpaper(
                clipping: clipping,
                style: style,
                screenSize: screenSize,
                typography: .default
            )
            await MainActor.run {
                previewImage = image
                isGenerating = false
            }
        }
    }

    private func applyPreviewWallpaper() {
        guard let clipping = sampleClipping, let screen = NSScreen.main else { return }
        // Render at full Retina resolution for actual wallpaper
        let fullSize = CGSize(
            width: screen.frame.size.width * screen.backingScaleFactor,
            height: screen.frame.size.height * screen.backingScaleFactor
        )
        guard let fullImage = generator.generateWallpaper(
            clipping: clipping,
            style: selectedStyle,
            screenSize: fullSize,
            typography: .default
        ) else { return }
        let manager = WallpaperManager(storageService: StorageService())
        try? manager.setWallpaper(image: fullImage)
    }
}
