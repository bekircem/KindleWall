import SwiftUI

/// The three groups of controls in the design editor's inspector.
///
/// These were three stacked sections on one scrolling page, which meant scrolling past two of
/// them to reach the third while the wallpaper they all describe sat in a narrow strip on the
/// side. As tabs only one group is on screen at a time, and the canvas takes the width the
/// other two gave up.
enum DesignTab: String, CaseIterable, Identifiable {
    case style, typography, background

    var id: String { rawValue }

    /// `String(localized:)`, not a bare literal. A `String`-typed title never reaches the
    /// String Catalog on its own, so these three shipped in English inside an otherwise
    /// Turkish window — the exact leak `CONTRIBUTING.md` warns about.
    var title: String {
        switch self {
        case .style:      return String(localized: "Style")
        case .typography: return String(localized: "Typography")
        case .background: return String(localized: "Background")
        }
    }

    /// Used for the VoiceOver label and the tooltip; the segmented control shows text.
    var icon: String {
        switch self {
        case .style:      return "paintpalette"
        case .typography: return "textformat"
        case .background: return "circle.lefthalf.filled"
        }
    }
}
