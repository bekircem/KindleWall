import SwiftUI

/// A labeled group on a consolidated settings page: a prominent header above its section
/// content.
///
/// Sits one step above `SettingsCard`'s own uppercased titles, giving a clear hierarchy
/// (group → card → row) on pages that gather several sections into one scrolling pane —
/// the macOS System Settings shape. Shared by "Tasarım" and "Davranış" so both read the same.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.leading, Theme.Spacing.xs)

            content
        }
    }
}
