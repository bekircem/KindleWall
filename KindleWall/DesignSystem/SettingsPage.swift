import SwiftUI

/// Scaffold for a focused settings sub-page.
///
/// Provides a vertically scrolling, centered readable column with consistent padding and
/// inter-card spacing. Each Loop-style sidebar page wraps its cards in this so they all share
/// the same layout rhythm. The navigation title is set from `title`.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                content
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(title)
    }
}
