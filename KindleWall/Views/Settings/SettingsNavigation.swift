import SwiftUI

/// Sidebar information architecture for the main window — Loop-style grouped, focused pages.
enum SidebarSection: String, CaseIterable, Identifiable {
    case general    = "Genel"
    case appearance = "Görünüm"
    case behavior   = "Davranış"
    case app        = "Uygulama"

    var id: String { rawValue }
}

/// A single sidebar destination. Carries its own title, icon, color, and section so the
/// sidebar and any breadcrumb stay in sync from one source of truth.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case currentQuote, library
    case style, typography, background
    case behavior
    case general, shortcuts, account, about

    var id: String { rawValue }

    var section: SidebarSection {
        switch self {
        case .currentQuote, .library:                return .general
        case .style, .typography, .background:       return .appearance
        case .behavior:                              return .behavior
        case .general, .shortcuts, .account, .about: return .app
        }
    }

    var title: String {
        switch self {
        case .currentQuote: return "Şu Anki Alıntı"
        case .library:      return "Kütüphane"
        case .style:        return "Stil"
        case .typography:   return "Tipografi"
        case .background:   return "Arka Plan"
        case .behavior:     return "Davranış"
        case .general:      return "Genel"
        case .shortcuts:    return "Kısayollar"
        case .account:      return "Hesap"
        case .about:        return "Hakkında"
        }
    }

    var icon: String {
        switch self {
        case .currentQuote: return "quote.bubble.fill"
        case .library:      return "books.vertical.fill"
        case .style:        return "paintpalette.fill"
        case .typography:   return "textformat"
        case .background:   return "drop.fill"
        case .behavior:     return "slider.horizontal.3"
        case .general:      return "gearshape.fill"
        case .shortcuts:    return "keyboard.fill"
        case .account:      return "person.crop.circle.fill"
        case .about:        return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .currentQuote: return .indigo
        case .library:      return .orange
        case .style:        return .purple
        case .typography:   return .pink
        case .background:   return .teal
        case .behavior:     return .blue
        case .general:      return Color(.systemGray)
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
    var onApplyNow: () -> Void = {}
}
