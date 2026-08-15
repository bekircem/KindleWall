import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

/// Registers a configurable global hotkey using the Carbon RegisterEventHotKey API.
/// Unlike NSEvent.addGlobalMonitorForEvents, Carbon hotkeys require NO Accessibility permission
/// and work in any app context. Accessibility is used only to pre-fill selected text (optional).
///
/// Main-actor isolated. This describes what the class already did rather than changing it: the
/// Carbon callback is file-scope C and hops to the main queue before touching anything here,
/// and `showCapturePanel` builds an `NSPanel` and an `NSHostingView` — AppKit work that is only
/// ever valid on the main thread. The annotation makes that a checked rule instead of a habit.
@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var capturePanel: NSPanel?

    private var currentKeyCode: UInt16 = 40
    private var currentModifiers: NSEvent.ModifierFlags = [.control, .option]

    // Unique four-char signature to identify our hotkey event ("KWLL")
    private static let signature: UInt32 = 0x4B574C4C
    private static let eventID: UInt32 = 1

    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    private init() {}

    // MARK: - Lifecycle

    func start() {
        let s = StorageService()
        currentKeyCode   = UInt16(s.hotkeyKeyCode)
        currentModifiers = NSEvent.ModifierFlags(rawValue: UInt(bitPattern: s.hotkeyModifiers))
        installCarbonHandler()
        registerHotKey()
    }

    func stop() {
        unregisterHotKey()
        if let h = eventHandlerRef { RemoveEventHandler(h); eventHandlerRef = nil }
    }

    /// Hot-reloads the hotkey binding without restarting the event handler.
    func updateHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        unregisterHotKey()
        currentKeyCode   = keyCode
        currentModifiers = modifiers
        registerHotKey()
    }

    /// Shows the QuickCapturePanel. Called from MenuBar button or programmatically.
    func showCapture(prefilledText: String = "") {
        showCapturePanel(prefilledText: prefilledText)
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    /// Called by the Carbon C callback when the hotkey fires.
    func handleHotkeyFired() {
        // Selected text is best-effort — works only when Accessibility is granted.
        let text = AXIsProcessTrusted() ? (selectedTextFromFrontApp() ?? "") : ""
        showCapturePanel(prefilledText: text)
    }

    // MARK: - Carbon registration

    private func installCarbonHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotkeyEventCallback,
            1, &spec,
            nil, &eventHandlerRef
        )
    }

    private func registerHotKey() {
        let hkID = EventHotKeyID(signature: Self.signature, id: Self.eventID)
        RegisterEventHotKey(
            UInt32(currentKeyCode),
            carbonModifiers(from: currentModifiers),
            hkID,
            GetApplicationEventTarget(),
            0, &hotKeyRef
        )
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey)  }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey)   }
        if flags.contains(.command) { mods |= UInt32(cmdKey)     }
        return mods
    }

    // MARK: - Selected text (Accessibility, optional)

    private func selectedTextFromFrontApp() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success,
              let ref = focusedRef,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let focused = ref as! AXUIElement
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextAttribute as CFString, &selectedRef
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
            backing: .buffered, defer: false
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
            onCancel: { [weak panel] in panel?.close() }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        self.capturePanel = panel
    }
}

// MARK: - Carbon C callback (file-scope so it can serve as a function pointer)

private func globalHotkeyEventCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hkID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    if hkID.signature == 0x4B574C4C {
        // Already hopping to the main queue; `assumeIsolated` states that fact for the compiler
        // rather than adding a second hop through a Task, which would let two rapid presses
        // arrive out of order.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { GlobalHotkeyManager.shared.handleHotkeyFired() }
        }
    }
    return noErr
}
