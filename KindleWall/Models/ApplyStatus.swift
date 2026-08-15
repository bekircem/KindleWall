import Foundation

/// Why the wallpaper is being applied.
///
/// Load-bearing rather than decorative: the reason decides whether the finished state may
/// offer to put the design back (a scheduler tick changed the *quote*, so offering to undo a
/// *design* there would be a lie), how long that finished state lingers, and what the status
/// row says.
enum ApplyReason: Equatable {
    /// The user pressed Uygula, chose a quote to apply, or undid a design change.
    case manual
    /// A design edit applied itself once the edits settled.
    case automatic
    /// The rotation timer fired and picked a new quote.
    case scheduler
    /// A launch-time repair of a blank or missing desktop wallpaper.
    case repair

    /// Whether finishing this apply may offer to restore the previous design.
    var offersDesignUndo: Bool {
        switch self {
        case .manual, .automatic: return true
        case .scheduler, .repair: return false
        }
    }

    /// How long the finished state stays on screen before fading back to `.idle`.
    var completionDwell: Duration {
        switch self {
        // Deliberately equal to the style-typography undo banner's own six seconds, so a style
        // click makes both appear and disappear together and reads as a single event.
        case .automatic: return .seconds(6)
        default:         return .seconds(2)
        }
    }
}

/// Where the desktop stands relative to the design the app is showing.
///
/// Replaces the old pair of loose `isApplying` / `applySuccess` booleans, which could not
/// express "waiting to apply", "applied but degraded", or "the preview is ahead of the
/// desktop" — and whose success flag was cleared by an unstored timer, so two applies close
/// together made the first one's timer wipe the second one's success early.
enum ApplyStatus: Equatable {
    /// The desktop matches; nothing in flight.
    case idle

    /// A design edit is waiting out the settle delay before it applies on its own.
    case pending(reason: ApplyReason, deadline: Date)

    /// Rendering and writing right now.
    case applying(reason: ApplyReason)

    /// On the desktop. `degraded` carries a warning about an apply that *succeeded* but had to
    /// fall back — this used to be written to `errorMessage`, so the user saw a green
    /// "Uygulandı" and a red error line at the same time.
    case applied(at: Date, reason: ApplyReason, degraded: String?)

    /// The apply failed; `message` is already user-facing Turkish.
    case failed(message: String)

    /// Automatic applying is switched off and the preview is ahead of the desktop.
    case unapplied

    var isApplying: Bool {
        if case .applying = self { return true }
        return false
    }

    var isApplied: Bool {
        if case .applied = self { return true }
        return false
    }

    /// Whether the user still has to do something for the design to reach the desktop.
    var needsManualApply: Bool {
        self == .unapplied
    }

    /// The reason behind the current state, when it has one.
    var reason: ApplyReason? {
        switch self {
        case let .pending(reason, _), let .applying(reason), let .applied(_, reason, _):
            return reason
        case .idle, .failed, .unapplied:
            return nil
        }
    }
}
