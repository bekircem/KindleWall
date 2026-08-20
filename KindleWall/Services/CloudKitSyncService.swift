import CloudKit
import CryptoKit
import Foundation
import Observation

/// Synchronizes user state, manual clippings, and book metadata overrides across the user's
/// Macs via the CloudKit private database.
///
/// **Lifecycle:** Started unconditionally at launch. The system iCloud account is the only
/// credential involved — `checkAccountAndBootstrap` reads `CKContainer.accountStatus()` and
/// puts every unavailable case into `SyncState` with a reason the UI can show.
///
/// **Conflict resolution:** Last-write-wins on scalars (server's `modificationDate`
/// is authoritative); set fields (favorites, shown, pinned, persistedIDs) take
/// the **union** of local and server before push to avoid losing concurrent adds.
///
/// **Triggers:**
/// 1. On start → full pull, then full push (if local has newer state)
/// 2. On `userStateChanged` / `manualClippingsChanged` / `bookOverridesChanged`
///    notifications → debounced push (2s) via `pendingPushTimer`
/// 3. On `cloudKitRemotePush` notification (APN from AppDelegate) → immediate pull
@MainActor
@Observable
final class CloudKitSyncService {
    // MARK: - Dependencies

    private let syncState: SyncState
    private let storage: StorageService
    private let container: CKContainer
    private var privateDatabase: CKDatabase { container.privateCloudDatabase }
    private let zoneID = CKRecordZone.ID(zoneName: SyncSchema.zoneName, ownerName: CKCurrentUserDefaultName)

    // MARK: - State

    private var isRunning = false
    private var pendingPushTimer: Timer?
    /// Guards against re-broadcasting notifications while applying remote changes.
    private var isApplyingRemoteChanges = false
    /// Guards against infinite recursion if a token-reset re-pull also reports
    /// `changeTokenExpired`. Flipped during the recovery `performPull()` call.
    private var isRecoveringFromExpiredToken = false
    /// Categories that need to push on next flush.
    private var pendingDirty: Set<DirtyCategory> = []

    /// Serializes sync cycles. A trigger that arrives mid-cycle sets `rerunRequested`
    /// so exactly one follow-up runs after the current cycle finishes — no overlapping
    /// push/pull, no status thrash.
    private var isSyncing = false
    private var rerunRequested = false

    private enum DirtyCategory: Hashable {
        case userState
        case manualClippings
        case bookOverrides
    }

    /// A unit of work in a sync cycle. Order within `runSync([...])` is significant.
    private enum SyncOp { case push, pull }

    /// Snapshot of "what we last synced with cloud" — drives deletion diffs and
    /// LWW-Element-Set semantics for the singleton UserState record's set fields.
    /// Invariant after each successful push or pull: snapshot == localCurrent.
    private struct SyncSnapshot: Codable, Equatable {
        var manualClippingIDs: Set<String> = []
        var bookOverrideTitles: Set<String> = []
        var favoriteClippingIDs: Set<String> = []
        var shownClippingIDs: Set<String> = []
        var persistedClippingIDs: Set<String> = []
        var pinnedBookTitles: Set<String> = []
        /// Hash of the singleton UserState payload at last successful sync. Lets a push
        /// skip a no-op re-save (which would otherwise bounce a silent push back to us).
        var userStateSignature: String = ""
    }

    // MARK: - Init

    init(syncState: SyncState, storage: StorageService) {
        self.syncState = syncState
        self.storage = storage
        self.container = CKContainer(identifier: SyncSchema.containerIdentifier)
    }

    // MARK: - Lifecycle

    /// Starts the sync engine. Idempotent; safe to call repeatedly.
    ///
    /// Call it unconditionally: `checkAccountAndBootstrap` reads `CKContainer.accountStatus()`
    /// and reports every unavailable case to `SyncState` itself, so there is nothing useful for
    /// a caller to check first.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        Task {
            await checkAccountAndBootstrap()
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleUserStateChanged),
                           name: Constants.Notifications.userStateChanged, object: nil)
        center.addObserver(self, selector: #selector(handleManualClippingsChanged),
                           name: Constants.Notifications.manualClippingsChanged, object: nil)
        center.addObserver(self, selector: #selector(handleBookOverridesChanged),
                           name: Constants.Notifications.bookOverridesChanged, object: nil)
        center.addObserver(self, selector: #selector(handleRemotePush),
                           name: Constants.Notifications.cloudKitRemotePush, object: nil)
    }

    /// Stops the sync engine. Local data is preserved.
    ///
    /// Nothing calls this today — the sign-out that used to was removed with Sign in with
    /// Apple. It stays as `start()`'s counterpart, and because the teardown it performs is
    /// real: an un-invalidated `Timer` outliving its owner is a bug this codebase has already
    /// shipped once, in `SchedulerService`.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        NotificationCenter.default.removeObserver(self)
        pendingPushTimer?.invalidate()
        pendingPushTimer = nil
        pendingDirty.removeAll()
        syncState.status = .disabled(reason: String(localized: "Sync stopped"))
    }

    /// User-initiated sync. Pushes any pending changes then pulls remote updates,
    /// as a single cycle (one `.syncing` → one `.idle`).
    func syncNow() async {
        await runSync([.push, .pull])
    }

    // MARK: - Bootstrap

    private func checkAccountAndBootstrap() async {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            syncState.status = .error(String(localized: "Could not read the iCloud status: \(error.localizedDescription)"))
            return
        }

        switch status {
        case .available:
            break
        case .noAccount:
            syncState.status = .disabled(reason: String(localized: "Sign in with your iCloud account"))
            return
        case .restricted:
            syncState.status = .disabled(reason: String(localized: "iCloud is restricted"))
            return
        case .couldNotDetermine, .temporarilyUnavailable:
            syncState.status = .disabled(reason: String(localized: "iCloud is unavailable right now"))
            return
        @unknown default:
            syncState.status = .disabled(reason: String(localized: "The iCloud status is unknown"))
            return
        }

        syncState.status = .syncing

        do {
            try await bootstrapZoneIfNeeded()
            try await bootstrapSubscriptionIfNeeded()
        } catch {
            syncState.status = .error(String(localized: "Setup failed: \(error.localizedDescription)"))
            return
        }

        // One cycle: pull remote state first, then push only genuinely-diverged local
        // data. The push methods skip no-op writes, so a device already in sync makes no
        // server change (and therefore receives no self-addressed silent push back).
        pendingDirty = [.userState, .manualClippings, .bookOverrides]
        await runSync([.pull, .push])
    }

    private func bootstrapZoneIfNeeded() async throws {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Constants.StorageKeys.cloudKitZoneCreated) { return }

        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await privateDatabase.save(zone)
        defaults.set(true, forKey: Constants.StorageKeys.cloudKitZoneCreated)
        // Fresh zone = no last-pushed state. Stale snapshot from a different
        // account would compute spurious deletions on first push.
        defaults.removeObject(forKey: Constants.StorageKeys.cloudKitSyncSnapshot)
    }

    private func bootstrapSubscriptionIfNeeded() async throws {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Constants.StorageKeys.cloudKitSubscriptionCreated) { return }

        let subscription = CKDatabaseSubscription(subscriptionID: SyncSchema.subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // silent push
        subscription.notificationInfo = notificationInfo

        _ = try await privateDatabase.save(subscription)
        defaults.set(true, forKey: Constants.StorageKeys.cloudKitSubscriptionCreated)
    }

    // MARK: - Notification handlers

    @objc private func handleUserStateChanged() {
        guard !isApplyingRemoteChanges else { return }
        pendingDirty.insert(.userState)
        schedulePush()
    }

    @objc private func handleManualClippingsChanged() {
        guard !isApplyingRemoteChanges else { return }
        pendingDirty.insert(.manualClippings)
        schedulePush()
    }

    @objc private func handleBookOverridesChanged() {
        guard !isApplyingRemoteChanges else { return }
        pendingDirty.insert(.bookOverrides)
        schedulePush()
    }

    @objc private func handleRemotePush() {
        Task { await runSync([.pull]) }
    }

    private func schedulePush() {
        pendingPushTimer?.invalidate()
        pendingPushTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.runSync([.push])
            }
        }
    }

    /// Runs one serialized sync cycle: a single `.syncing` at the start and a single
    /// `markIdle()` at the end. Triggers that arrive mid-cycle are coalesced into one
    /// follow-up run via `rerunRequested`, so push/pull never overlap or thrash status.
    private func runSync(_ ops: [SyncOp]) async {
        guard isRunning else { return }
        guard !isSyncing else { rerunRequested = true; return }
        isSyncing = true
        defer {
            isSyncing = false
            if rerunRequested {
                rerunRequested = false
                Task { await self.runSync([.push, .pull]) }
            }
        }

        syncState.status = .syncing
        for op in ops {
            switch op {
            case .push: await performPendingPushes()
            case .pull: await performPull()
            }
            if case .error = syncState.status { return }   // surface failure, skip markIdle
        }
        markIdle()
    }

    /// Pushes any dirty categories. Does not own `syncState.status` (only records a
    /// failure); `runSync` owns the syncing/idle transitions.
    private func performPendingPushes() async {
        guard isRunning, !pendingDirty.isEmpty else { return }
        let toPush = pendingDirty
        pendingDirty.removeAll()
        do {
            if toPush.contains(.userState) { try await pushUserState() }
            if toPush.contains(.manualClippings) { try await pushManualClippings() }
            if toPush.contains(.bookOverrides) { try await pushBookOverrides() }
            // After a successful push, our local state matches cloud — record
            // the snapshot so the next push can compute correct deletion diffs.
            saveSnapshotFromLocal()
        } catch {
            syncState.status = .error(error.localizedDescription)
        }
    }

    private func markIdle() {
        syncState.status = .idle
        let now = Date()
        syncState.lastSyncedAt = now
        UserDefaults.standard.set(now, forKey: Constants.StorageKeys.cloudKitLastSyncedAt)
    }

    // MARK: - Push: UserState (singleton)

    private func pushUserState() async throws {
        let snapshot = loadSnapshot()

        // Skip a no-op re-save: if local UserState is unchanged since the last sync, saving
        // would still bump the record's change-tag and bounce a silent push back to this very
        // device via the CKDatabaseSubscription — the sync feedback loop. Nothing to push.
        if computeUserStateSignature() == snapshot.userStateSignature { return }

        let recordID = CKRecord.ID(recordName: SyncSchema.userStateRecordName, zoneID: zoneID)

        // Fetch server's copy to compute LWW-Element-Set merges and capture the change tag.
        let serverRecord: CKRecord
        do {
            serverRecord = try await privateDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // First push — create new record. Snapshot is empty, so server section
            // of LWW formula degenerates to `local`.
            let newRecord = CKRecord(recordType: SyncSchema.RecordType.userState, recordID: recordID)
            populateUserState(into: newRecord, serverSource: nil, snapshot: snapshot)
            _ = try await privateDatabase.save(newRecord)
            return
        }

        populateUserState(into: serverRecord, serverSource: serverRecord, snapshot: snapshot)
        do {
            _ = try await privateDatabase.save(serverRecord)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Stale change tag — recompute merges against the latest server record.
            if let latest = error.serverRecord {
                populateUserState(into: latest, serverSource: latest, snapshot: snapshot)
                _ = try await privateDatabase.save(latest)
            } else {
                throw error
            }
        }
    }

    private func populateUserState(into record: CKRecord, serverSource: CKRecord?, snapshot: SyncSnapshot) {
        let f = SyncSchema.UserStateField.self

        // Scalars — local wins.
        record[f.selectedStyle] = storage.selectedStyle.rawValue as NSString
        record[f.scheduleInterval] = storage.scheduleInterval.rawValue as NSString
        if let date = storage.customScheduleDate {
            record[f.customScheduleDate] = date as NSDate
        } else {
            record[f.customScheduleDate] = nil
        }
        record[f.rotationMode] = storage.rotationMode.rawValue as NSString
        record[f.currentBookTitle] = storage.currentBookTitle as NSString?
        record[f.launchAtLogin] = storage.launchAtLogin ? 1 : 0 as NSNumber
        record[f.showNotifications] = storage.showNotifications ? 1 : 0 as NSNumber
        record[f.applyToAllSpaces] = storage.applyToAllSpaces ? 1 : 0 as NSNumber
        record[f.hotkeyKeyCode] = storage.hotkeyKeyCode as NSNumber
        record[f.hotkeyModifiers] = storage.hotkeyModifiers as NSNumber

        // Codable structs as JSON strings.
        if let typographyJSON = try? String(data: JSONEncoder().encode(storage.typography), encoding: .utf8) {
            record[f.typographyJSON] = typographyJSON as NSString
        }
        if let longQuoteJSON = try? String(data: JSONEncoder().encode(storage.longQuote), encoding: .utf8) {
            record[f.longQuoteJSON] = longQuoteJSON as NSString
        }

        // Set fields — LWW-Element-Set: server state + local adds − local removes.
        // This preserves concurrent additions on other devices AND propagates
        // explicit removals on this one.
        record[f.favoriteClippingIDs] = lwwElementSet(
            local: Set(storage.favoriteClippingIDs.map { $0.uuidString }),
            lastPushed: snapshot.favoriteClippingIDs,
            server: serverSource?[f.favoriteClippingIDs] as? [String]
        ) as NSArray
        record[f.shownClippingIDs] = lwwElementSet(
            local: Set(storage.shownClippingIDs.map { $0.uuidString }),
            lastPushed: snapshot.shownClippingIDs,
            server: serverSource?[f.shownClippingIDs] as? [String]
        ) as NSArray
        record[f.persistedClippingIDs] = lwwElementSet(
            local: Set(storage.persistedClippingIDs.map { $0.uuidString }),
            lastPushed: snapshot.persistedClippingIDs,
            server: serverSource?[f.persistedClippingIDs] as? [String]
        ) as NSArray
        record[f.pinnedBookTitles] = lwwElementSet(
            local: Set(storage.pinnedBookTitles),
            lastPushed: snapshot.pinnedBookTitles,
            server: serverSource?[f.pinnedBookTitles] as? [String]
        ) as NSArray
    }

    /// LWW-Element-Set CRDT for a single set field.
    /// - `adds`    = local − lastPushed (explicit local additions since last push)
    /// - `removes` = lastPushed − local (explicit local removals since last push)
    /// - `final`   = (server − removes) ∪ adds — preserves other devices' state while
    ///               applying our delta.
    private func lwwElementSet(local: Set<String>, lastPushed: Set<String>, server: [String]?) -> [String] {
        let serverSet = Set(server ?? [])
        let adds = local.subtracting(lastPushed)
        let removes = lastPushed.subtracting(local)
        return Array(serverSet.subtracting(removes).union(adds))
    }

    // MARK: - Push: ManualClippings

    private func pushManualClippings() async throws {
        let snapshot = loadSnapshot()
        let clippings = storage.manualClippings
        let localIDs = Set(clippings.map { $0.id.uuidString })
        let toDelete = snapshot.manualClippingIDs.subtracting(localIDs)

        // Skip the operation entirely when there's nothing to push or delete.
        guard !clippings.isEmpty || !toDelete.isEmpty else { return }

        let records = clippings.map { clipping -> CKRecord in
            let recordID = CKRecord.ID(recordName: clipping.id.uuidString, zoneID: zoneID)
            let record = CKRecord(recordType: SyncSchema.RecordType.manualClipping, recordID: recordID)
            let f = SyncSchema.ManualClippingField.self
            record[f.bookTitle] = clipping.bookTitle as NSString
            record[f.author] = clipping.author as NSString?
            record[f.text] = clipping.text as NSString
            record[f.page] = clipping.page as NSString?
            record[f.location] = clipping.location as NSString?
            record[f.dateAdded] = clipping.dateAdded as NSDate?
            record[f.type] = clipping.type.rawValue as NSString
            return record
        }
        let recordIDsToDelete = toDelete.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        // .allKeys: local is the source of truth for manual clippings (LWW).
        try await modifyRecords(saving: records, deleting: recordIDsToDelete, savePolicy: .allKeys)
    }

    // MARK: - Push: BookOverrides

    private func pushBookOverrides() async throws {
        let snapshot = loadSnapshot()
        let overrides = storage.bookMetadataOverrides
        let localTitles = Set(overrides.keys)
        let toDeleteTitles = snapshot.bookOverrideTitles.subtracting(localTitles)

        guard !overrides.isEmpty || !toDeleteTitles.isEmpty else { return }

        let records = overrides.values.map { override -> CKRecord in
            let recordID = CKRecord.ID(recordName: overrideRecordName(for: override.originalTitle), zoneID: zoneID)
            let record = CKRecord(recordType: SyncSchema.RecordType.bookOverride, recordID: recordID)
            let f = SyncSchema.BookOverrideField.self
            record[f.originalTitle] = override.originalTitle as NSString
            record[f.displayTitle] = override.displayTitle as NSString
            record[f.displayAuthor] = override.displayAuthor as NSString?
            return record
        }
        let recordIDsToDelete = toDeleteTitles.map {
            CKRecord.ID(recordName: overrideRecordName(for: $0), zoneID: zoneID)
        }
        try await modifyRecords(saving: records, deleting: recordIDsToDelete, savePolicy: .allKeys)
    }

    /// SHA256-based record name — collision-free, deterministic, fits the
    /// CloudKit record name format (`[A-Za-z0-9_-]`, ≤255 chars).
    private func overrideRecordName(for originalTitle: String) -> String {
        let digest = SHA256.hash(data: Data(originalTitle.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "ovr-" + String(hex.prefix(60))
    }

    private func modifyRecords(
        saving: [CKRecord],
        deleting: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .changedKeys
    ) async throws {
        let op = CKModifyRecordsOperation(recordsToSave: saving, recordIDsToDelete: deleting)
        op.savePolicy = savePolicy
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume(returning: ())
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            privateDatabase.add(op)
        }
    }

    // MARK: - Pull

    /// Fetches and applies remote changes. Does not own `syncState.status` (only records a
    /// failure); `runSync` owns the syncing/idle transitions.
    private func performPull() async {
        guard isRunning else { return }

        let token = loadChangeToken()
        let zoneConfig = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
            previousServerChangeToken: token,
            resultsLimit: nil,
            desiredKeys: nil
        )
        let op = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: zoneConfig]
        )

        var changedRecords: [CKRecord] = []
        var deletedRecordIDs: [(CKRecord.ID, CKRecord.RecordType)] = []

        op.recordWasChangedBlock = { _, result in
            if case .success(let record) = result {
                changedRecords.append(record)
            }
        }
        op.recordWithIDWasDeletedBlock = { recordID, type in
            deletedRecordIDs.append((recordID, type))
        }

        var newToken: CKServerChangeToken?
        op.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
            newToken = token
        }
        op.recordZoneFetchResultBlock = { _, result in
            if case .success(let res) = result {
                newToken = res.serverChangeToken
            }
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                op.fetchRecordZoneChangesResultBlock = { result in
                    switch result {
                    case .success: continuation.resume(returning: ())
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
                privateDatabase.add(op)
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            // Server invalidated our change token (rare: iCloud sign-out/in,
            // schema reset, or token aged out). Drop it and re-pull from scratch.
            saveChangeToken(nil)
            guard !isRecoveringFromExpiredToken else {
                // The recovery pull also failed — bail to avoid infinite recursion.
                syncState.status = .error(String(localized: "Sync could not recover"))
                return
            }
            isRecoveringFromExpiredToken = true
            await performPull()
            isRecoveringFromExpiredToken = false
            return
        } catch {
            syncState.status = .error(error.localizedDescription)
            return
        }

        applyRemoteChanges(records: changedRecords, deletions: deletedRecordIDs)
        if let newToken { saveChangeToken(newToken) }
        // After applying remote changes, our local state matches cloud.
        saveSnapshotFromLocal()
    }

    private func applyRemoteChanges(records: [CKRecord], deletions: [(CKRecord.ID, CKRecord.RecordType)]) {
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        for record in records {
            switch record.recordType {
            case SyncSchema.RecordType.userState:
                applyUserStateRecord(record)
            case SyncSchema.RecordType.manualClipping:
                applyManualClippingRecord(record)
            case SyncSchema.RecordType.bookOverride:
                applyBookOverrideRecord(record)
            default:
                continue
            }
        }

        for (recordID, type) in deletions {
            switch type {
            case SyncSchema.RecordType.manualClipping:
                deleteManualClipping(recordName: recordID.recordName)
            case SyncSchema.RecordType.bookOverride:
                deleteBookOverride(recordName: recordID.recordName)
            default:
                continue
            }
        }
    }

    private func applyUserStateRecord(_ record: CKRecord) {
        let f = SyncSchema.UserStateField.self

        // Another device may still be on the eight-style build; migrate its value rather
        // than dropping the sync.
        if let raw = record[f.selectedStyle] as? String, let style = WallpaperStyle(persistedRawValue: raw) {
            storage.selectedStyle = style
        }
        if let raw = record[f.scheduleInterval] as? String, let interval = ScheduleInterval(rawValue: raw) {
            storage.scheduleInterval = interval
        }
        storage.customScheduleDate = record[f.customScheduleDate] as? Date
        if let raw = record[f.rotationMode] as? String, let mode = RotationMode(rawValue: raw) {
            storage.rotationMode = mode
        }
        storage.currentBookTitle = record[f.currentBookTitle] as? String
        if let val = record[f.launchAtLogin] as? Int { storage.launchAtLogin = val != 0 }
        if let val = record[f.showNotifications] as? Int { storage.showNotifications = val != 0 }
        if let val = record[f.applyToAllSpaces] as? Int { storage.applyToAllSpaces = val != 0 }
        if let val = record[f.hotkeyKeyCode] as? Int { storage.hotkeyKeyCode = val }
        if let val = record[f.hotkeyModifiers] as? Int { storage.hotkeyModifiers = val }

        if let json = record[f.typographyJSON] as? String,
           let data = json.data(using: .utf8),
           let typography = try? JSONDecoder().decode(TypographySettings.self, from: data) {
            storage.typography = typography
        }
        if let json = record[f.longQuoteJSON] as? String,
           let data = json.data(using: .utf8),
           let longQuote = try? JSONDecoder().decode(LongQuoteSettings.self, from: data) {
            storage.longQuote = longQuote
        }

        if let arr = record[f.favoriteClippingIDs] as? [String] {
            storage.favoriteClippingIDs = Set(arr.compactMap(UUID.init(uuidString:)))
        }
        if let arr = record[f.shownClippingIDs] as? [String] {
            storage.shownClippingIDs = Set(arr.compactMap(UUID.init(uuidString:)))
        }
        if let arr = record[f.persistedClippingIDs] as? [String] {
            storage.persistedClippingIDs = Set(arr.compactMap(UUID.init(uuidString:)))
        }
        if let arr = record[f.pinnedBookTitles] as? [String] {
            storage.pinnedBookTitles = arr
        }
    }

    private func applyManualClippingRecord(_ record: CKRecord) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let f = SyncSchema.ManualClippingField.self
        guard let bookTitle = record[f.bookTitle] as? String,
              let text = record[f.text] as? String else { return }
        let type = (record[f.type] as? String).flatMap(ClippingType.init(rawValue:)) ?? .highlight
        let clipping = Clipping(
            id: id,
            bookTitle: bookTitle,
            author: record[f.author] as? String,
            text: text,
            page: record[f.page] as? String,
            location: record[f.location] as? String,
            dateAdded: record[f.dateAdded] as? Date,
            type: type,
            isManualEntry: true
        )
        var current = storage.manualClippings
        if let idx = current.firstIndex(where: { $0.id == id }) {
            current[idx] = clipping
        } else {
            current.append(clipping)
        }
        storage.manualClippings = current
    }

    private func applyBookOverrideRecord(_ record: CKRecord) {
        let f = SyncSchema.BookOverrideField.self
        guard let originalTitle = record[f.originalTitle] as? String,
              let displayTitle = record[f.displayTitle] as? String else { return }
        let override = BookMetadataOverride(
            originalTitle: originalTitle,
            displayTitle: displayTitle,
            displayAuthor: record[f.displayAuthor] as? String
        )
        var current = storage.bookMetadataOverrides
        current[originalTitle] = override
        storage.bookMetadataOverrides = current
    }

    private func deleteManualClipping(recordName: String) {
        guard let id = UUID(uuidString: recordName) else { return }
        var current = storage.manualClippings
        current.removeAll { $0.id == id }
        storage.manualClippings = current
    }

    private func deleteBookOverride(recordName: String) {
        // Sanitized record names lose the original title, so locate by suffix-matching
        // sanitized names. Fall back to full reload from server if necessary.
        var current = storage.bookMetadataOverrides
        for (originalTitle, _) in current where overrideRecordName(for: originalTitle) == recordName {
            current.removeValue(forKey: originalTitle)
        }
        storage.bookMetadataOverrides = current
    }

    // MARK: - Snapshot persistence

    private func loadSnapshot() -> SyncSnapshot {
        guard let data = UserDefaults.standard.data(forKey: Constants.StorageKeys.cloudKitSyncSnapshot),
              let snap = try? JSONDecoder().decode(SyncSnapshot.self, from: data)
        else { return SyncSnapshot() }
        return snap
    }

    /// Writes a snapshot that mirrors the current local state. Called after a
    /// successful push (cloud now matches local) or after a pull's batch has
    /// been applied (local was just synced to match cloud).
    private func saveSnapshotFromLocal() {
        let snap = SyncSnapshot(
            manualClippingIDs: Set(storage.manualClippings.map { $0.id.uuidString }),
            bookOverrideTitles: Set(storage.bookMetadataOverrides.keys),
            favoriteClippingIDs: Set(storage.favoriteClippingIDs.map { $0.uuidString }),
            shownClippingIDs: Set(storage.shownClippingIDs.map { $0.uuidString }),
            persistedClippingIDs: Set(storage.persistedClippingIDs.map { $0.uuidString }),
            pinnedBookTitles: Set(storage.pinnedBookTitles),
            userStateSignature: computeUserStateSignature()
        )
        guard let data = try? JSONEncoder().encode(snap) else { return }
        UserDefaults.standard.set(data, forKey: Constants.StorageKeys.cloudKitSyncSnapshot)
    }

    /// Deterministic hash of the singleton UserState payload (scalars + Codable structs +
    /// sorted set fields). Lets `pushUserState` skip a no-op re-save so an unchanged device
    /// makes no server change — which is what stops the self-addressed silent-push loop.
    private func computeUserStateSignature() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func json<T: Encodable>(_ value: T) -> String {
            (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }

        let parts: [String] = [
            storage.selectedStyle.rawValue,
            storage.scheduleInterval.rawValue,
            storage.customScheduleDate.map { String($0.timeIntervalSince1970) } ?? "·",
            storage.rotationMode.rawValue,
            storage.currentBookTitle ?? "·",
            storage.launchAtLogin ? "1" : "0",
            storage.showNotifications ? "1" : "0",
            storage.applyToAllSpaces ? "1" : "0",
            String(storage.hotkeyKeyCode),
            String(storage.hotkeyModifiers),
            json(storage.typography),
            json(storage.longQuote),
            storage.favoriteClippingIDs.map { $0.uuidString }.sorted().joined(separator: ","),
            storage.shownClippingIDs.map { $0.uuidString }.sorted().joined(separator: ","),
            storage.persistedClippingIDs.map { $0.uuidString }.sorted().joined(separator: ","),
            storage.pinnedBookTitles.sorted().joined(separator: ",")
        ]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Change token persistence

    private func loadChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: Constants.StorageKeys.cloudKitChangeToken) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveChangeToken(_ token: CKServerChangeToken?) {
        guard let token else {
            UserDefaults.standard.removeObject(forKey: Constants.StorageKeys.cloudKitChangeToken)
            return
        }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: Constants.StorageKeys.cloudKitChangeToken)
        }
    }
}
