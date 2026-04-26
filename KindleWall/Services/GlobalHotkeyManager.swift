import AppKit
import ApplicationServices
import SwiftUI

/// Listens for the global hotkey (⌃⌥K) and shows a floating QuickCapturePanel
/// pre-filled with the selected text from the frontmost application.
/// Requires Accessibility permission; prompts the user on first use.
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var capturePanel: NSPanel?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.isHotkeyEvent(event) == true else { return }
            DispatchQueue.main.async { self?.handleHotkey() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.isHotkeyEvent(event) == true else { return event }
            DispatchQueue.main.async { self?.handleHotkey() }
            return nil // consume so the app doesn't also handle it
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor  = nil }
    }

    // MARK: - Hotkey detection

    // keyCode 40 = K on all keyboard layouts
    private func isHotkeyEvent(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control, .option]
            && event.keyCode == 40
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
        // Close any previously open panel
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
        let alert = NSAlert()
        alert.messageText = "Erişilebilirlik İzni Gerekli"
        alert.informativeText = """
            KindleWall'ın ⌃⌥K kısayoluyla seçili metni okuyabilmesi için \
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
}
