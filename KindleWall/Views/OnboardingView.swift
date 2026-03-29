import SwiftUI

/// Three-step onboarding flow for first-time users.
struct OnboardingView: View {
    var onComplete: (URL, WallpaperStyle, ScheduleInterval) -> Void

    @State private var currentStep: Int = 0
    @State private var selectedFileURL: URL?
    @State private var selectedStyle: WallpaperStyle = .minimalDark
    @State private var selectedInterval: ScheduleInterval = .hourly

    // Preview state
    @State private var parsedClippings: [Clipping] = []
    @State private var sampleClipping: Clipping?
    @State private var previewImage: NSImage?
    @State private var isGenerating: Bool = false

    private let parser = ClippingsParser()
    private let generator = WallpaperGenerator()

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                fileSelectStep.tag(1)
                styleStep.tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Geri") {
                        withAnimation(.spring(duration: 0.3)) {
                            currentStep -= 1
                        }
                    }
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

                Spacer()

                if currentStep < 2 {
                    Button("İleri") {
                        withAnimation(.spring(duration: 0.3)) {
                            currentStep += 1
                        }
                        if currentStep == 2 {
                            loadClippingsAndPreview()
                        }
                    }
                    .disabled(currentStep == 1 && selectedFileURL == nil)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Başla") {
                        if let url = selectedFileURL {
                            onComplete(url, selectedStyle, selectedInterval)
                        }
                    }
                    .disabled(selectedFileURL == nil)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 700, height: 580)
        .onChange(of: selectedStyle) { _, _ in
            generatePreview()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: Constants.Icons.currentQuote)
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("KindleWall'a Hoş Geldiniz")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Kindle alıntılarınızı masaüstü duvar kağıdına dönüştürün.\nHer gün farklı bir ilham kaynağı.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    private var fileSelectStep: some View {
        VStack(spacing: 16) {
            Text("Dosyanızı Seçin")
                .font(.title)
                .fontWeight(.bold)

            Text("Kindle cihazınızdaki My Clippings.txt dosyasını seçin.")
                .foregroundStyle(.secondary)

            // Drop area
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(.secondary)
                .frame(height: 150)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

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
                .padding(.horizontal, 40)

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
        }
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

        do {
            parsedClippings = try parser.parse(fileURL: url)
            pickRandomClipping()
            generatePreview()
        } catch {
            // Silently fail — user will see empty preview
        }
    }

    private func pickRandomClipping() {
        sampleClipping = parsedClippings.randomElement()
    }

    private func generatePreview() {
        guard let clipping = sampleClipping else { return }
        guard let screen = NSScreen.main else { return }

        isGenerating = true
        let screenSize = CGSize(
            width: screen.frame.size.width * screen.backingScaleFactor,
            height: screen.frame.size.height * screen.backingScaleFactor
        )
        let style = selectedStyle

        Task.detached {
            let image = generator.generateWallpaper(
                clipping: clipping,
                style: style,
                screenSize: screenSize
            )
            await MainActor.run {
                previewImage = image
                isGenerating = false
            }
        }
    }

    private func applyPreviewWallpaper() {
        guard let image = previewImage else { return }
        let manager = WallpaperManager(storageService: StorageService())
        try? manager.setWallpaper(image: image)
    }
}
