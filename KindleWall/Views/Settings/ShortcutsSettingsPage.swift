import SwiftUI

/// "Shortcuts" page — global text-capture hotkey + optional Accessibility permission.
struct ShortcutsSettingsPage: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        SettingsPage(title: "Shortcuts") {
            SettingsCard(
                title: "Metin Yakalama",
                footnote: "Herhangi bir uygulamada metin seçip kısayola basınca QuickCapture paneli açılır."
            ) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(alignment: .center, spacing: Theme.Spacing.m) {
                        IconTile(symbol: "keyboard.fill", color: .indigo)
                        Text("Capture Shortcut")
                            .font(.body)
                        Spacer()
                        HotkeyRecorderButton()
                    }

                    Divider()

                    HStack(spacing: 6) {
                        if accessibilityGranted {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Accessibility is granted — selected text is filled in automatically")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        } else {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                            Text("Optional: with Accessibility granted, selected text arrives in the panel automatically")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Grant Permission") {
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
