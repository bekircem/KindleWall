import SwiftUI

/// Displays user account info when signed in, or a sign-in prompt when not.
struct AccountView: View {
    @Environment(AuthState.self) private var authState
    @Environment(AuthService.self) private var authService
    @Environment(SyncState.self) private var syncState
    @Environment(CloudKitSyncService.self) private var cloudKitSync
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                switch authState.status {
                case .unknown:
                    ProgressView("Kontrol ediliyor...")
                        .padding(.top, Theme.Spacing.xxl)

                case .unauthenticated:
                    signInSection

                case .authenticated(let profile):
                    profileSection(profile: profile)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.xxl)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Hesap")
    }

    // MARK: - Sign In

    private var signInSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Hesabınıza Giriş Yapın")
                .font(.title2)
                .fontWeight(.bold)

            Text("Apple Hesabınızla giriş yaparak favorilerinizi, ayarlarınızı ve düzenlemelerinizi cihazlarınız arasında senkronize edin.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            SignInWithAppleButton {
                authService.signIn()
            }
            .frame(width: 240, height: 44)
        }
    }

    // MARK: - Profile

    private func profileSection(profile: UserProfile) -> some View {
        VStack(spacing: Theme.Spacing.xl) {
            // Avatar placeholder
            ZStack {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 80, height: 80)
                Text(avatarInitials(profile))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text(profile.greeting)
                    .font(.title2)
                    .fontWeight(.bold)

                if let email = profile.email {
                    Text(email)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("Üye: \(profile.createdAt.formatted(.dateTime.month(.wide).year()))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()
                .frame(maxWidth: 300)

            // Sync status
            SettingsCard {
                HStack(spacing: Theme.Spacing.m) {
                    syncStatusIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Senkronizasyon")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(syncStatusDescription)
                            .font(.caption)
                            .foregroundStyle(syncStatusForeground)
                    }
                    Spacer()
                    if case .idle = syncState.status {
                        Button("Şimdi") {
                            Task { await cloudKitSync.syncNow() }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .frame(maxWidth: 320)

            // Subscription status (Phase 5)
            SettingsCard {
                HStack(spacing: Theme.Spacing.m) {
                    IconTile(symbol: "crown.fill", color: .yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Abonelik")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Ücretsiz Plan")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(Theme.Spacing.l)
            }
            .frame(maxWidth: 320)

            // Actions
            VStack(spacing: Theme.Spacing.m) {
                Button("Çıkış Yap") {
                    authService.signOut()
                }
                .foregroundStyle(.primary)

                Button("Hesabı Sil") {
                    showDeleteConfirm = true
                }
                .foregroundStyle(.red)
                .font(.caption)
            }
        }
        .confirmationDialog(
            "Hesabınızı silmek istediğinize emin misiniz?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Hesabı Sil", role: .destructive) {
                authService.deleteAccount()
            }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("Bu işlem yerel oturumunuzu sonlandırır. Apple ID bağlantısını tamamen kaldırmak için appleid.apple.com adresinden uygulamayı yetkili uygulamalar listesinden çıkarabilirsiniz.")
        }
    }

    // MARK: - Helpers

    private func avatarInitials(_ profile: UserProfile) -> String {
        guard let name = profile.displayName else { return "?" }
        let parts = name.components(separatedBy: " ")
        let initials = parts.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined().uppercased()
    }

    // MARK: - Sync status presentation

    @ViewBuilder private var syncStatusIcon: some View {
        switch syncState.status {
        case .disabled:
            Image(systemName: "icloud.slash")
                .foregroundStyle(.secondary)
        case .idle:
            Image(systemName: "checkmark.icloud")
                .foregroundStyle(.green)
        case .syncing:
            ProgressView()
                .controlSize(.small)
        case .error:
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.red)
        }
    }

    private var syncStatusDescription: String {
        switch syncState.status {
        case .disabled(let reason):
            return reason
        case .idle:
            guard let date = syncState.lastSyncedAt else { return "Hazır" }
            // A just-completed sync reads as "az önce". RelativeDateTimeFormatter would
            // otherwise render the near-now instant as the nonsensical "0 saniye sonra".
            if Date().timeIntervalSince(date) < 10 {
                return "Son senkronizasyon: az önce"
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            formatter.locale = Locale(identifier: "tr_TR")
            return "Son senkronizasyon: " + formatter.localizedString(for: date, relativeTo: Date())
        case .syncing:
            return "Senkronize ediliyor…"
        case .error(let msg):
            return msg
        }
    }

    private var syncStatusForeground: HierarchicalShapeStyle {
        if case .error = syncState.status { return .primary }
        return .tertiary
    }
}
