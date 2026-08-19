import SwiftUI

/// iCloud sync status.
///
/// This screen used to be an account page built on Sign in with Apple. That capability is not
/// available to apps distributed with a Developer ID — Apple will not issue a provisioning
/// profile for one — and it never carried its weight here anyway: CloudKit's private database
/// runs on the system iCloud account, so signing in a second time bought nothing but a gate.
struct AccountView: View {
    @Environment(SyncState.self) private var syncState
    @Environment(CloudKitSyncService.self) private var cloudKitSync

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                header
                statusCard
                if case .disabled = syncState.status {
                    systemSettingsHint
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.xxl)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("iCloud")
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            IconTile(symbol: "icloud", color: .blue, size: 56)

            Text("iCloud Eşitleme")
                .font(.title2.weight(.bold))

            Text("Favorilerin, gösterilmiş alıntıların ve düzenlemelerin Mac'lerin arasında eşitlenir. Veriler yalnızca senin özel iCloud veritabanına yazılır; bu projenin bir sunucusu yok.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        SettingsCard {
            HStack(spacing: Theme.Spacing.m) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text("Durum")
                        .font(.subheadline.weight(.medium))
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundStyle(statusForeground)
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
        .frame(maxWidth: 360)
    }

    /// Only shown while sync is unavailable — the fix is always in System Settings, never here.
    private var systemSettingsHint: some View {
        Button("Sistem Ayarları'nda iCloud'u Aç") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.glass)
    }

    // MARK: - Presentation

    @ViewBuilder private var statusIcon: some View {
        switch syncState.status {
        case .disabled:
            Image(systemName: "icloud.slash").foregroundStyle(.secondary)
        case .idle:
            Image(systemName: "checkmark.icloud").foregroundStyle(.green)
        case .syncing:
            ProgressView().controlSize(.small)
        case .error:
            Image(systemName: "exclamationmark.icloud").foregroundStyle(.red)
        }
    }

    private var statusDescription: String {
        switch syncState.status {
        case .disabled(let reason):
            return reason
        case .idle:
            guard let date = syncState.lastSyncedAt else { return "Hazır" }
            // A just-completed sync reads as "az önce". RelativeDateTimeFormatter would
            // otherwise render the near-now instant as the nonsensical "0 saniye sonra".
            if Date().timeIntervalSince(date) < 10 {
                return "Son eşitleme: az önce"
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            formatter.locale = Locale(identifier: "tr_TR")
            return "Son eşitleme: " + formatter.localizedString(for: date, relativeTo: Date())
        case .syncing:
            return "Eşitleniyor…"
        case .error(let msg):
            return msg
        }
    }

    private var statusForeground: HierarchicalShapeStyle {
        if case .error = syncState.status { return .primary }
        return .tertiary
    }
}
