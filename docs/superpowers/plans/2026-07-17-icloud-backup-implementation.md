# MateDrive iCloud Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in iCloud backup and safe restore for MateDrive's local database and non-secret settings without slowing normal page navigation.

**Architecture:** The existing SQLite actor gains a tested online-backup primitive. A `CloudBackupCoordinator` actor composes database snapshots, sanitized settings, a CloudKit private-database service, retention, and rollback. The Settings-only view model renders cached backup metadata immediately and refreshes CloudKit in the background. Normal Home and feature pages never access CloudKit.

**Tech Stack:** Swift 6.3, SwiftUI, CloudKit, CryptoKit, SQLite3, XCTest, XcodeGen, iOS 18+.

## Global Constraints

- Never read, encode, upload, or restore Keychain secrets.
- Never copy the live SQLite file with file-system copy APIs.
- Keep automatic backup disabled until explicit user consent.
- Keep the newest three successful cloud backups.
- Restore must create a safety snapshot and roll back on every post-replacement failure.
- Opening Home, Features, or any second- or third-level page must not query CloudKit.
- The Cloud Backup page shows cached metadata before any network result.
- All temporary files use complete-file protection and are removed after success, failure, or cancellation.
- All visible text is localized in English and Simplified Chinese.

---

### Task 1: Add SQLite Online Backup And Integrity Primitives

**Files:**
- Modify: `MateDriveApp/Core/Persistence/SQLiteDatabase.swift`
- Modify: `MateDriveApp/Core/Persistence/AppDatabaseProvider.swift`
- Create: `MateDriveTests/Persistence/SQLiteBackupTests.swift`

**Interfaces:**
- Produces: `SQLiteDatabase.backup(to:)`, `SQLiteDatabase.restore(from:)`, `SQLiteDatabase.integrityCheck()`, and schema-version inspection.
- Consumes: the existing actor-owned SQLite connection.

- [ ] **Step 1: Write failing online-backup tests**

Create a temporary live database, insert records, create a snapshot, write more rows, and assert that the snapshot opens independently with only the pre-backup state. Add tests for reverse restore, integrity check, and rejection of a corrupt file.

- [ ] **Step 2: Run `SQLiteBackupTests`; expect compile failure**

- [ ] **Step 3: Implement bounded SQLite backup stepping**

Use `sqlite3_backup_init`, `sqlite3_backup_step`, `sqlite3_backup_remaining`, and `sqlite3_backup_finish`. Retry `SQLITE_BUSY` and `SQLITE_LOCKED` with a small bounded sleep. Always call `sqlite3_backup_finish`, close the temporary connection, and surface the final SQLite error code.

```swift
public func backup(to destinationURL: URL) throws -> SQLiteBackupMetadata
public func restore(from sourceURL: URL) throws
public func integrityCheck() throws -> Bool
public func schemaVersion() throws -> Int
```

The destination file must be created outside the live database directory and receive `.completeFileProtection` after the backup completes.

- [ ] **Step 4: Implement reverse online backup for restore**

Open the validated source read-only and use it as the backup source while the actor-owned live connection is the destination. Do not replace, rename, or close the live database file.

- [ ] **Step 5: Run `SQLiteBackupTests`; expect PASS**
- [ ] **Step 6: Commit with `feat: add safe sqlite backup primitives`**

### Task 2: Define Backup Models, Preferences, And Sanitized Settings

**Files:**
- Create: `MateDriveApp/Core/Backup/CloudBackupModels.swift`
- Create: `MateDriveApp/Core/Backup/CloudBackupPreferencesStore.swift`
- Create: `MateDriveApp/Core/Backup/DatabaseBackupProvider.swift`
- Create: `MateDriveTests/Backup/CloudBackupModelsTests.swift`
- Create: `MateDriveTests/Backup/DatabaseBackupProviderTests.swift`

**Interfaces:**
- Produces: `CloudBackupKind`, `CloudBackupDescriptor`, `CloudBackupPreferences`, `DatabaseBackupArtifact`, and `DatabaseBackupProviding`.
- Consumes: `AppSettingsStore`, `LiveAppDatabaseProvider`, CryptoKit SHA-256, and temporary-file storage.

- [ ] **Step 1: Write failing model and provider tests**

Cover stable JSON versioning, automatic-backup default-off behavior, consent persistence, SHA-256, byte count, schema version, temporary cleanup, and settings round-trip. Inject a Keychain spy and assert it receives zero calls.

- [ ] **Step 2: Run focused backup tests; expect compile failure**

- [ ] **Step 3: Add versioned backup domain models**

```swift
public enum CloudBackupKind: String, Codable, Sendable { case manual, automatic }

public struct CloudBackupDescriptor: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let createdAt: Date
    public let kind: CloudBackupKind
    public let formatVersion: Int
    public let databaseSchemaVersion: Int
    public let appVersion: String
    public let databaseByteCount: Int64
    public let databaseSHA256: String
}
```

Keep automatic-backup consent and last-success metadata in `CloudBackupPreferencesStore`, separate from `AppSettings`, so restoring old settings cannot silently enable cloud backup.

- [ ] **Step 4: Implement database artifact creation and validation**

Create snapshots through Task 1 only. Encode `AppSettings` directly because authentication secrets live in Keychain, but keep the provider independent from `KeychainStore`. Validate file size, checksum, supported format, schema compatibility, and SQLite integrity before exposing an artifact for restore.

- [ ] **Step 5: Run model/provider tests; expect PASS**
- [ ] **Step 6: Commit with `feat: add versioned backup artifacts`**

### Task 3: Implement A Testable CloudKit Private-Database Service

**Files:**
- Create: `MateDriveApp/Core/Backup/CloudBackupService.swift`
- Create: `MateDriveApp/Core/Backup/CloudKitBackupService.swift`
- Create: `MateDriveTests/Backup/InMemoryCloudBackupService.swift`
- Create: `MateDriveTests/Backup/CloudKitBackupServiceMappingTests.swift`

**Interfaces:**
- Produces: account-status, list, upload, download, delete-one, and delete-all operations behind `CloudBackupServicing`.
- Consumes: `CKContainer`, private database, `MateDriveBackupZone`, `CKAsset`, and encrypted settings values.

- [ ] **Step 1: Write failing record-mapping and error-mapping tests**

Cover all record fields, encrypted `settingsData`, sorted newest-first results, missing asset rejection, no-account, quota, rate-limit retry date, cancellation, and service-unavailable errors. Tests use pure record mappers and the in-memory service, not a live iCloud account.

- [ ] **Step 2: Run focused service tests; expect compile failure**

- [ ] **Step 3: Define the narrow service protocol**

```swift
public protocol CloudBackupServicing: Sendable {
    func accountStatus() async throws -> CloudBackupAccountStatus
    func listBackups() async throws -> [CloudBackupDescriptor]
    func upload(_ artifact: DatabaseBackupArtifact, kind: CloudBackupKind) async throws -> CloudBackupDescriptor
    func download(_ descriptor: CloudBackupDescriptor) async throws -> DownloadedCloudBackup
    func delete(_ descriptor: CloudBackupDescriptor) async throws
    func deleteAll() async throws
}
```

- [ ] **Step 4: Implement CloudKit records in the private database**

Create the custom zone idempotently. Store the snapshot as `CKAsset`, write `settingsData` through `record.encryptedValues`, and put no location, vehicle, server, or device data in queryable fields. Copy downloaded assets into a protected temporary file before returning because CloudKit owns the original asset URL.

- [ ] **Step 5: Run service mapping tests; expect PASS**
- [ ] **Step 6: Commit with `feat: add private cloud backup service`**

### Task 4: Build Backup Scheduling, Retention, And Cancellation

**Files:**
- Create: `MateDriveApp/Core/Backup/CloudBackupCoordinator.swift`
- Create: `MateDriveTests/Backup/CloudBackupCoordinatorTests.swift`

**Interfaces:**
- Produces: serialized manual/automatic backup operations, eligibility, retention, and operation state.
- Consumes: `CloudBackupServicing`, `DatabaseBackupProviding`, preferences, clock, application version, and cancellation.

- [ ] **Step 1: Write failing coordinator tests**

Cover default opt-out, disclosure acceptance, 24-hour automatic eligibility, successful-full-sync prerequisite, one-operation-at-a-time behavior, expiration cancellation, upload-before-retention order, newest-three retention, nonblocking cleanup warnings, retry-after dates, and temporary-file cleanup.

- [ ] **Step 2: Run `CloudBackupCoordinatorTests`; expect compile failure**

- [ ] **Step 3: Implement actor-isolated state and eligibility**

```swift
public actor CloudBackupCoordinator {
    public func createManualBackup() async throws -> CloudBackupDescriptor
    public func createAutomaticBackup(after report: BackgroundRefreshReport) async
    public func cancelCurrentOperation() async
    public func listBackups(forceRefresh: Bool) async throws -> [CloudBackupDescriptor]
}
```

Return cached descriptors immediately when `forceRefresh` is false. Only the Settings backup screen asks for a forced background refresh.

- [ ] **Step 4: Implement upload, preference update, and retention sequencing**

Persist a successful timestamp only after CloudKit confirms the saved record. Then delete all but the newest three. Treat retention failure as a warning and preserve the new backup.

- [ ] **Step 5: Run coordinator tests; expect PASS**
- [ ] **Step 6: Commit with `feat: coordinate cloud backup retention`**

### Task 5: Implement Verified Restore With Automatic Rollback

**Files:**
- Modify: `MateDriveApp/Core/Backup/CloudBackupCoordinator.swift`
- Create: `MateDriveApp/Core/Backup/BackupCacheInvalidator.swift`
- Modify: `MateDriveApp/App/AppDataSyncLifecycleController.swift`
- Modify: `MateDriveApp/App/RootView.swift`
- Modify: `MateDriveTests/Backup/CloudBackupCoordinatorTests.swift`
- Create: `MateDriveTests/Backup/CloudBackupRestoreTests.swift`

**Interfaces:**
- Produces: `restore(_:)`, rollback, restore-completed notification, and one root cache reload.
- Consumes: sync-idle control, migrations, settings store, cache clearing, widget reload, and Task 1 reverse backup.

- [ ] **Step 1: Add failing restore pipeline tests**

Build fault-injection tests for download, checksum, schema, integrity, safety snapshot, replacement, migration, settings restore, cache clear, and root reload. For each failure after replacement, assert that the original database and original settings are restored before sync resumes.

- [ ] **Step 2: Run restore tests; expect failure**

- [ ] **Step 3: Implement a scoped sync suspension token**

Wait for active sync to finish, prevent a new sync during restore, and guarantee release in `defer`. Normal navigation continues to render cached data until the restore progress surface becomes active.

- [ ] **Step 4: Implement the exact restore pipeline**

Validate first, create safety snapshots, reverse-backup the downloaded database, run current migrations, restore sanitized settings while preserving Keychain and local cloud-consent preferences, clear disposable caches, reload widget timelines, then publish one restore-completed event. Roll back both database and settings on any post-replacement error.

- [ ] **Step 5: Observe restore completion once at Root**

Clear stale view-model snapshots, reload shared dashboard state from the restored cache, and increment one app-wide cache revision. Do not recreate navigation stacks and do not add per-page restore observers.

- [ ] **Step 6: Run restore and lifecycle tests; expect PASS**
- [ ] **Step 7: Commit with `feat: add verified cloud restore rollback`**

### Task 6: Add The Cached-First Cloud Backup Settings UI

**Files:**
- Create: `MateDriveApp/Features/Settings/CloudBackupViewModel.swift`
- Create: `MateDriveApp/Features/Settings/CloudBackupView.swift`
- Modify: `MateDriveApp/Features/Settings/SettingsView.swift`
- Modify: `MateDriveApp/Features/Settings/PrivacyDataView.swift`
- Modify: `MateDriveApp/Resources/Localizable.xcstrings`
- Create: `MateDriveTests/Features/CloudBackupViewModelTests.swift`
- Modify: `MateDriveTests/Localization/LocalizationCoverageTests.swift`

**Interfaces:**
- Produces: cloud-account status, opt-in control, last success, three cached rows, manual backup, restore, delete, and delete-all UI.
- Consumes: `CloudBackupCoordinator` only; no direct CloudKit or SQLite calls.

- [ ] **Step 1: Write failing view-model tests**

Cover cached descriptors visible in initial state, background refresh without clearing rows, one-time disclosure, automatic-backup toggle rollback on failure, disabled duplicate actions, destructive restore confirmation, delete confirmation, retry, credential reminder after restore, and localized error presentation.

- [ ] **Step 2: Run focused view-model tests; expect compile failure**

- [ ] **Step 3: Implement a main-actor view model**

The initializer reads cached metadata synchronously. `loadRemoteMetadata()` updates in the background and never changes the screen to a blank loading state. Expose one operation enum so backup, restore, and delete cannot overlap.

- [ ] **Step 4: Build the Settings-only screen**

Use a standard `List`/`Form`, native toggles, progress labels, menus, and destructive confirmation dialogs. Add the Cloud Backup row beside Privacy and Local Data. Do not add a tab badge, launch check, dashboard warning, or CloudKit request outside this screen.

- [ ] **Step 5: Add complete English and Simplified Chinese strings**
- [ ] **Step 6: Run view-model and localization tests plus `make localization-audit`; expect PASS**
- [ ] **Step 7: Commit with `feat: add iCloud backup settings`**

### Task 7: Wire Automatic Backup And App Store Capabilities

**Files:**
- Modify: `MateDriveApp/App/MateDriveApp.swift`
- Modify: `MateDriveApp/Core/Sync/AppDataSyncCoordinator.swift`
- Modify: `MateDriveApp/MateDriveApp.entitlements`
- Modify: `project.yml`
- Regenerate: `MateDrive.xcodeproj/project.pbxproj`
- Modify: `MateDriveApp/PrivacyInfo.xcprivacy`
- Modify: `docs/support/privacy.html`
- Modify: `docs/support/index.html`
- Modify: `docs/release/app-store-submission.md`
- Modify: `scripts/audit_release_archive.py`
- Modify: `scripts/test_audit_release_archive.py`
- Modify: `MateDriveTests/Smoke/AppStoreReadinessTests.swift`

**Interfaces:**
- Produces: one post-success auto-backup hook and releasable CloudKit entitlements/documentation.
- Consumes: successful full-sync reports only.

- [ ] **Step 1: Add failing readiness and background-hook tests**

Assert the app target has the CloudKit service and `iCloud.com.matedrive.ios` container, the widget has neither, release docs require production-schema deployment, privacy text describes route/history backup, and unsuccessful sync reports cannot trigger automatic backup.

- [ ] **Step 2: Run readiness tests; expect failure**

- [ ] **Step 3: Trigger automatic backup after successful full sync**

Call the coordinator from the existing lifecycle/background completion boundary. The call must be detached from page presentation, cancel when background time expires, and remain a no-op when consent, account status, or the 24-hour window makes it ineligible.

- [ ] **Step 4: Add capabilities and regenerate the project**

Add only these app-target entitlements:

```xml
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.com.matedrive.ios</string></array>
```

Run `make generate`, inspect the generated signing settings, and verify the widget target remains unchanged.

- [ ] **Step 5: Update privacy, support, and release documentation**

Document opt-in behavior, private-database storage, excluded credentials, user deletion, and the manual developer-portal steps for container creation and CloudKit development-to-production schema deployment.

- [ ] **Step 6: Run readiness, audit-script, sync, and localization tests; expect PASS**
- [ ] **Step 7: Commit with `feat: configure iCloud backup release support`**

### Task 8: Verify Data Safety, Navigation Performance, And Device Behavior

**Files:**
- Create: `docs/qa/icloud-backup-2026-07.md`
- Modify: `docs/parity/manual-test-checklist.md`

**Interfaces:**
- Consumes: completed backup, tabs, cache-first pages, simulator, connected iPhone, and developer iCloud account.
- Produces: reproducible release evidence and any explicitly recorded external blocker.

- [ ] **Step 1: Run all focused backup, navigation, lifecycle, localization, readiness, and migration tests**
- [ ] **Step 2: Run `make test-build`, `make test`, `make localization-audit`, and `make app-store-technical-audit`; expect PASS**
- [ ] **Step 3: Run repeated-navigation regression checks**

Open the same second- and third-level pages repeatedly, switch tabs, start/stop drive playback, and move maps. Confirm cached content renders immediately, no foreground duplicate fetch starts, playback remains responsive, maps reset after three seconds, and toolbar controls do not overlap.

- [ ] **Step 4: Test backup and restore on a signed-in physical iPhone**

Accept disclosure, create manual backup, relaunch offline, alter local data, restore, confirm credentials remain device-local, test delete-one/delete-all, and verify the app remains usable when iCloud is signed out. Record CloudKit container or provisioning blockers rather than bypassing them.

- [ ] **Step 5: Install the verified build on the connected iPhone with `make install-device`**
- [ ] **Step 6: Record test counts, simulator/device versions, timing observations, CloudKit environment, and screenshots in the QA document**
- [ ] **Step 7: Commit with `test: verify iCloud backup and cached navigation`**
