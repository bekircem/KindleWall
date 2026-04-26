import AppKit
import ApplicationServices
import SwiftUI

/// Listens for a configurable global hotkey and shows a floating QuickCapturePanel
/// pre-filled with the selected text from the frontmost application.
/// Requires Accessibility permission; prompts the user on first use.
/// Default hotkey: ⌃⌥K (configurable via Ayarlar → Klavye Kısayolları).
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var capturePanel: NSPanel?

    private var currentKeyCode: UInt16 = 40
    private var currentModifiers: NSEvent.ModifierFlags = [.control, .option]

    private init() {}

    // MARK: - Lifecycle

    /// Whether the app currently has Accessibility permission.
    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    func start() {
        let s = StorageService()
        currentKeyCode   = UInt16(s.hotkeyKeyCode)
        currentModifiers = NSEvent.ModifierFlags(rawValue: UInt(bitPattern: s.hotkeyModifiers))
        registerMonitors()
        // addGlobalMonitorForEvents for .keyDown silently does nothing without Accessibility.
        // Trigger the system permission dialog proactively so the user isn't left wondering.
        promptForAccessibilityIfNeeded()
    }

    /// Triggers the system Accessibility permission dialog (if not yet granted).
    /// macOS adds the app to System Settings → Accessibility and opens settings.
    /// Safe to call multiple times — no-op when permission is already granted.
    func promptForAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    func stop() {
        stopMonitors()
    }

    /// Updates the active hotkey and immediately restarts the event monitors.
    func updateHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        stopMonitors()
        currentKeyCode   = keyCode
        currentModifiers = modifiers
        registerMonitors()
    }

    /// Shows the QuickCapturePanel with optional pre-filled text.
    /// Called from the menu bar button (no selected text) or programmatically.
    func showCapture(prefilledText: String = "") {
        showCapturePanel(prefilledText: prefilledText)
    }

    // MARK: - Monitor management

    private func registerMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.isHotkeyEvent(event) == true else { return }
            DispatchQueue.main.async { self?.handleHotkey() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.isHotkeyEvent(event) == true else { return event }
            DispatchQueue.main.async { self?.handleHotkey() }
            return nil
        }
    }

    private func stopMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor  = nil }
    }

    // MARK: - Hotkey detection

    private func isHotkeyEvent(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == currentModifiers
            && event.keyCode == currentKeyCode
    }

    // MARK: - Capture flow

    private func handleHotkey() {
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermission()
            return
        }
        let text = selectedTextFromFrontApp() ?? ""
        showCapturePanel(prefilledText: text)
    }

    private func selectedTextFromFrontApp() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let ref = focusedRef, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return nil
        }
        let focused = ref as! AXUIElement
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success else { return nil }
        return selectedRef as? String
    }

    // MARK: - Panel

    private func showCapturePanel(prefilledText: String) {
        capturePanel?.close()

        let books: [(title: String, author: String?)] = {
            guard let vm = AppEnvironment.shared.mainViewModel else { return [] }
            var seen = Set<String>()
            return vm.clippings.compactMap { c in
                guard !seen.contains(c.bookTitle) else { return nil }
                seen.insert(c.bookTitle)
                return (title: c.bookTitle, author: c.author)
            }.sorted { $0.title < $1.title }
        }()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "KindleWall — Alıntı Yakala"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.center()

        let view = QuickCaptureView(
            prefilledText: prefilledText,
            existingBooks: books,
            onSave: { [weak panel] title, author, text, page in
                AppEnvironment.shared.mainViewModel?.addManualClipping(
                    bookTitle: title, author: author, text: text, page: page
                )
                panel?.close()
            },
            onCancel: { [weak panel] in
                panel?.close()
            }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        self.capturePanel = panel
    }

    // MARK: - Accessibility permission

    private func requestAccessibilityPermission() {
        let hotkeyLabel = hotkeyDisplayString()
        let alert = NSAlert()
        alert.messageText = "Erişilebilirlik İzni Gerekli"
        alert.informativeText = """
            KindleWall'ın \(hotkeyLabel) kısayoluyla seçili metni okuyabilmesi için \
            Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik'te \
            KindleWall'a izin vermen gerekiyor.
            """
        alert.addButton(withTitle: "Ayarlara Git")
        alert.addButton(withTitle: "İptal")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    private func hotkeyDisplayString() -> String {
        HotkeyRecorderButton.formatHotkey(keyCode: currentKeyCode, modifiers: currentModifiers)
    }
}
