import SwiftUI

/// Sidebar information architecture for the main window — Loop-style grouped, focused pages.
enum SidebarSection: String, CaseIterable, Identifiable {
    // "Wallpaper" rather than "General": the old name collided with the *item* also called
    // "General" further down, so the sidebar used the same word for two different things.
    case wallpaper = "Wallpaper"
    case content   = "Content"
    case behavior  = "Behavior"
    case app       = "App"

    var id: String { rawValue }

    /// The sidebar's group heading.
    ///
    /// Separate from `rawValue`, which is an identifier rather than copy: reading the heading
    /// off the raw value left the four group titles in English inside a Turkish build.
    var title: String {
        switch self {
        case .wallpaper: return String(localized: "Wallpaper")
        case .content:   return String(localized: "Content")
        case .behavior:  return String(localized: "Behavior")
        case .app:       return String(localized: "App")
        }
    }

    /// The one hue every item in this section wears.
    ///
    /// The section the app exists for gets the brand accent; the rest step back in cool and
    /// neutral tones so the sidebar reads as four groups, not eight decorations. All three of
    /// those are dark enough to keep the white glyph `IconTile` gives them — the amber is not,
    /// and its dark glyph is the one place that reversal is meant to be noticed.
    var tint: Color {
        switch self {
        case .wallpaper: return Theme.Palette.accent
        case .content:   return .indigo
        case .behavior:  return .blue
        case .app:       return Theme.Palette.neutralTile
        }
    }
}

/// A single sidebar destination. Carries its own title, icon, color, and section so the
/// sidebar and any breadcrumb stay in sync from one source of truth.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case currentQuote, design
    case library
    case behavior
    case settings, shortcuts, account, about

    var id: String { rawValue }

    var section: SidebarSection {
        switch self {
        case .currentQuote, .design:                  return .wallpaper
        case .library:                                return .content
        case .behavior:                               return .behavior
        case .settings, .shortcuts, .account, .about: return .app
        }
    }

    /// `String(localized:)`, not a bare literal: this value is also used to sort the list and
    /// is handed to `Text` as a resolved string, so it has to come out of the catalog here.
    var title: String {
        switch self {
        case .currentQuote: return String(localized: "Current Quote")
        case .design:       return String(localized: "Design")
        case .library:      return String(localized: "Library")
        case .behavior:     return String(localized: "Behavior")
        case .settings:     return String(localized: "Settings")
        case .shortcuts:    return String(localized: "Shortcuts")
        case .account:      return "iCloud"
        case .about:        return String(localized: "About")
        }
    }

    var icon: String {
        switch self {
        case .currentQuote: return "quote.bubble.fill"
        case .design:       return "paintpalette.fill"
        case .library:      return "books.vertical.fill"
        case .behavior:     return "slider.horizontal.3"
        case .settings:     return "gearshape.fill"
        case .shortcuts:    return "keyboard.fill"
        case .account:      return "icloud.fill"
        case .about:        return "info.circle.fill"
        }
    }

    /// Tile color, derived from the section instead of picked per item.
    ///
    /// The per-item list held eight entries drawn from six hues, two of them repeats
    /// (indigo twice, gray twice), and the colors encoded nothing — so they read as
    /// decoration rather than as landmarks. Deriving from the section makes the grouping
    /// the thing the color says.
    var color: Color { section.tint }

    static func items(in section: SidebarSection) -> [SidebarItem] {
        allCases.filter { $0.section == section }
    }
}

/// Bundles the callbacks settings pages use to push changes into the live `MainViewModel`.
/// Centralizes wiring in `MainView` instead of threading many closures through the sidebar switch.
struct SettingsActions {
    var onFileSelected: (URL) -> Void = { _ in }
    /// Re-read the file already on record, through the stored bookmark — no file picker.
    var onCheckForNewClippings: () -> Void = {}
    var onStyleChanged: (WallpaperStyle) -> Void = { _ in }
    var onTypographyChanged: () -> Void = {}
    var onScheduleChanged: (ScheduleInterval, Date?) -> Void = { _, _ in }
    var onRotationModeChanged: (RotationMode) -> Void = { _ in }
    var onPinnedBooksChanged: (Set<String>) -> Void = { _ in }
    var onRestorePreviousWallpaper: () -> Void = {}
    /// Picks a *new quote* and applies it — "Change Now".
    var onApplyNow: () -> Void = {}
    /// Applies the current design without touching the quote.
    var onApplyDesignNow: () -> Void = {}
}
