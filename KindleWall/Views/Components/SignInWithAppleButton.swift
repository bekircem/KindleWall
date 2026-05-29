import AppKit
import AuthenticationServices
import SwiftUI

/// SwiftUI wrapper around `ASAuthorizationAppleIDButton`. Apple's HIG requires
/// using their native button (not a custom one) for Sign in with Apple.
struct SignInWithAppleButton: NSViewRepresentable {
    var type: ASAuthorizationAppleIDButton.ButtonType = .signIn
    var style: ASAuthorizationAppleIDButton.Style = .black
    var action: () -> Void

    func makeNSView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: type, style: style)
        button.target = context.coordinator
        button.action = #selector(Coordinator.tapped)
        button.cornerRadius = 8
        return button
    }

    func updateNSView(_ nsView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
    }
}
