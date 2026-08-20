import SwiftUI

/// A labeled group on a consolidated settings page: a prominent header above its section
/// content.
///
/// Sits one step above `SettingsCard`'s own uppercased titles, giving a clear hierarchy
/// (group → card → row) on pages that gather several sections into one scrolling pane —
/// the macOS System Settings shape. Shared by "Design" and "Behavior" so both read the same.
struct SettingsGroup<Content: View>: View {
    /// See `SettingsPage.title` for why this is a key rather than a `String`.
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title)
                .font(Theme.Typography.groupTitle)
                .foregroundStyle(.primary)
                .padding(.leading, Theme.Spacing.xs)

            content
        }
    }
}
