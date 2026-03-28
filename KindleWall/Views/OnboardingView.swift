import SwiftUI

/// Three-step onboarding flow for first-time users.
struct OnboardingView: View {
    var onComplete: (URL, WallpaperStyle, ScheduleInterval) -> Void

    @State private var currentStep: Int = 0
    @State private var selectedFileURL: URL?
    @State private var selectedStyle: WallpaperStyle = .minimalDark
    @State private var selectedInterval: ScheduleInterval = .hourly

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
        .frame(width: 600, height: 450)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: Constants.Icons.currentQuote)
                .font(.system(size: 64))
                .foregroundStyle(.accent)

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
        VStack(spacing: 16) {
            Text("Stil ve Zamanlama")
                .font(.title)
                .fontWeight(.bold)

            Text("Varsayılan duvar kağıdı stilinizi ve değişim sıklığını seçin.")
                .foregroundStyle(.secondary)

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
