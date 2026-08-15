import SwiftUI

/// "Kısayollar" page — global text-capture hotkey + optional Accessibility permission.
struct ShortcutsSettingsPage: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        SettingsPage(title: "Kısayollar") {
            SettingsCard(
                title: "Metin Yakalama",
                footnote: "Herhangi bir uygulamada metin seçip kısayola basınca QuickCapture paneli açılır."
            ) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(alignment: .center, spacing: Theme.Spacing.m) {
                        IconTile(symbol: "keyboard.fill", color: .indigo)
                        Text("Yakalama Kısayolu")
                            .font(.body)
                        Spacer()
                        HotkeyRecorderButton()
                    }

                    Divider()

                    HStack(spacing: 6) {
                        if accessibilityGranted {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Erişilebilirlik izni var — seçili metin otomatik doldurulur")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        } else {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                            Text("Opsiyonel: Erişilebilirlik izni verilirse seçili metin panele otomatik gelir")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("İzin Ver") {
                                GlobalHotkeyManager.shared.openAccessibilitySettings()
                            }
                            .font(.caption).buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
        .onAppear { accessibilityGranted = AXIsProcessTrusted() }
        // Granting the permission happens in System Settings, so the user comes back to a page
        // that is already on screen — `onAppear` alone never fires again and the row kept
        // insisting the permission was missing.
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification
            ) {
                accessibilityGranted = AXIsProcessTrusted()
            }
        }
    }
}
