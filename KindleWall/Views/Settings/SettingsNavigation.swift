import SwiftUI

/// Sidebar information architecture for the main window — Loop-style grouped, focused pages.
enum SidebarSection: String, CaseIterable, Identifiable {
    // "Duvar Kağıdı" rather than "Genel": the old name collided with the *item* also called
    // "Genel" further down, so the sidebar used the same word for two different things.
    case wallpaper = "Duvar Kağıdı"
    case content   = "İçerik"
    case behavior  = "Davranış"
    case app       = "Uygulama"

    var id: String { rawValue }
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

    var title: String {
        switch self {
        case .currentQuote: return "Şu Anki Alıntı"
        case .design:       return "Tasarım"
        case .library:      return "Kütüphane"
        case .behavior:     return "Davranış"
        case .settings:     return "Ayarlar"
        case .shortcuts:    return "Kısayollar"
        case .account:      return "Hesap"
        case .about:        return "Hakkında"
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
        case .account:      return "person.crop.circle.fill"
        case .about:        return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .currentQuote: return .indigo
        case .design:       return .purple
        case .library:      return .orange
        case .behavior:     return .blue
        case .settings:     return Color(.systemGray)
        case .shortcuts:    return .indigo
        case .account:      return .cyan
        case .about:        return .gray
        }
    }

    static func items(in section: SidebarSection) -> [SidebarItem] {
        allCases.filter { $0.section == section }
    }
}

/// Bundles the callbacks settings pages use to push changes into the live `MainViewModel`.
/// Centralizes wiring in `MainView` instead of threading many closures through the sidebar switch.
struct SettingsActions {
    var onFileSelected: (URL) -> Void = { _ in }
    var onStyleChanged: (WallpaperStyle) -> Void = { _ in }
    var onTypographyChanged: () -> Void = {}
    var onScheduleChanged: (ScheduleInterval, Date?) -> Void = { _, _ in }
    var onRotationModeChanged: (RotationMode) -> Void = { _ in }
    var onPinnedBooksChanged: (Set<String>) -> Void = { _ in }
    var onRestorePreviousWallpaper: () -> Void = {}
    /// Picks a *new quote* and applies it — "Şimdi Değiştir".
    var onApplyNow: () -> Void = {}
    /// Applies the current design without touching the quote.
    var onApplyDesignNow: () -> Void = {}
}
