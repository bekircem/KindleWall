import SwiftUI

/// Displays user account info when signed in, or a sign-in prompt when not.
struct AccountView: View {
    @Environment(AuthState.self) private var authState

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                switch authState.status {
                case .unknown:
                    ProgressView("Kontrol ediliyor...")

                case .unauthenticated:
                    signInSection

                case .authenticated(let profile):
                    profileSection(profile: profile)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(32)
        }
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

            // Placeholder — will be replaced with ASAuthorizationAppleIDButton wrapper
            Button {} label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                    Text("Apple ile Giriş Yap")
                }
                .frame(width: 240, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .disabled(true) // Disabled until Apple Developer enrollment
            .help("Apple Developer hesabı gerektirir")

            Text("Apple Developer hesabı yapılandırıldıktan sonra aktif olacaktır.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Profile

    private func profileSection(profile: UserProfile) -> some View {
        VStack(spacing: 24) {
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

            // Sync status (Phase 3)
            GroupBox {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Senkronizasyon")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Yakında aktif olacak")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 300)

            // Subscription status (Phase 5)
            GroupBox {
                HStack {
                    Image(systemName: "crown")
                        .foregroundStyle(.secondary)
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
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 300)

            Spacer(minLength: 20)

            // Actions
            VStack(spacing: 12) {
                Button("Çıkış Yap") {
                    // Phase 1 completion: wire to AuthService.signOut()
                }
                .foregroundStyle(.primary)

                Button("Hesabı Sil") {
                    // Phase 1 completion: wire to AuthService.deleteAccount()
                }
                .foregroundStyle(.red)
                .font(.caption)
            }
        }
    }

    // MARK: - Helpers

    private func avatarInitials(_ profile: UserProfile) -> String {
        guard let name = profile.displayName else { return "?" }
        let parts = name.components(separatedBy: " ")
        let initials = parts.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined().uppercased()
    }
}
