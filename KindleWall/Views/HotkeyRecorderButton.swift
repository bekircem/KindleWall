import SwiftUI
import AppKit

/// Displays the current global text-capture hotkey and allows the user to record a new one.
/// Saves directly to StorageService and hot-reloads GlobalHotkeyManager on change.
struct HotkeyRecorderButton: View {
    @State private var keyCode: UInt16
    @State private var modifiers: NSEvent.ModifierFlags
    @State private var isRecording = false
    @State private var monitor: Any?

    private static let defaultKeyCode: UInt16 = 40
    private static let defaultModifiers: NSEvent.ModifierFlags = [.control, .option]

    init() {
        let s = StorageService()
        _keyCode   = State(initialValue: UInt16(s.hotkeyKeyCode))
        _modifiers = State(initialValue: NSEvent.ModifierFlags(rawValue: UInt(bitPattern: s.hotkeyModifiers)))
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording
                     ? "Kısayol basın... (Esc = iptal)"
                     : Self.formatHotkey(keyCode: keyCode, modifiers: modifiers))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isRecording ? Color.orange : Color.primary)
                    .frame(minWidth: 120, alignment: .center)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .orange : .accentColor)

            Button("Varsayılana Dön") {
                stopRecording()
                applyHotkey(keyCode: Self.defaultKeyCode, modifiers: Self.defaultModifiers)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onDisappear { stopRecording() }
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Esc cancels recording without changing the hotkey
            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }

            // Require at least one modifier so bare letters can't be set
            guard !flags.isEmpty else { return event }

            self.applyHotkey(keyCode: event.keyCode, modifiers: flags)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func applyHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode   = keyCode
        self.modifiers = modifiers
        stopRecording()

        let s = StorageService()
        s.hotkeyKeyCode   = Int(keyCode)
        s.hotkeyModifiers = Int(bitPattern: UInt(modifiers.rawValue))

        GlobalHotkeyManager.shared.updateHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Formatting (static so GlobalHotkeyManager can reuse)

    static func formatHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        modifiersString(modifiers) + keyCodeString(keyCode)
    }

    private static func modifiersString(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    private static func keyCodeString(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A",  1: "S",  2: "D",  3: "F",  4: "H",  5: "G",  6: "Z",  7: "X",
            8: "C",  9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
           16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
           37: "L", 38: "J", 40: "K", 41: ";", 43: ",", 45: "N", 46: "M", 47: ".",
           18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
           24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
           36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦",
          123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End"
        ]
        return map[code] ?? "(\(code))"
    }
}
