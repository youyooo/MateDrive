# MateDrive iCloud Backup Design

**Date:** 2026-07-17  
**Status:** Approved direction and scope; awaiting written-spec review  
**Product:** MateDrive iOS

## Purpose

Give users an opt-in way to back up MateDrive's persistent local data to their own iCloud account and restore it after reinstalling the app or moving to another iPhone. The feature uses the user's CloudKit private database. It is backup and restore, not live multi-device synchronization.

The backup must preserve valuable synchronized history and user-created metadata without uploading TeslaMate credentials or disposable caches. A failed backup or restore must never make the current local database unusable.

## Scope

The first release provides:

- manual backup;
- optional automatic backup after successful background synchronization;
- a list of the three newest cloud backups;
- backup status, date, app version, and size;
- restore with compatibility and integrity checks;
- deletion of one backup or all cloud backups;
- an in-app privacy explanation and a way to disable automatic backup.

The first release does not provide live record synchronization, backup sharing, web access, credential synchronization, user-visible iCloud Drive documents, or merging two different MateDrive databases.

## CloudKit Storage

MateDrive uses one CloudKit container:

`iCloud.com.matedrive.ios`

Backups are stored in the user's private database in a custom zone named `MateDriveBackupZone`. The record type is `MateDriveBackup`. Each backup is one record with these fields:

- `createdAt`: date, queryable and sortable;
- `kind`: `automatic` or `manual`;
- `formatVersion`: backup-format integer;
- `databaseSchemaVersion`: SQLite schema version;
- `appVersion`: app version that created the backup;
- `databaseByteCount`: snapshot size;
- `databaseSHA256`: snapshot integrity checksum;
- `databaseAsset`: `CKAsset` containing the SQLite snapshot;
- `settingsData`: encrypted JSON data containing sanitized `AppSettings`.

The database asset is used because it is a binary file larger than a normal record field. CloudKit encrypts private-database assets by default. `settingsData` uses `CKRecord.encryptedValues`. No vehicle name, route, address, coordinate, server URL, or device name is placed in queryable metadata fields.

The CloudKit development schema must include the record type, encrypted field, zone use, and a sortable/queryable `createdAt` field. The schema is deployed to production before the App Store build is submitted.

## Backup Contents

Each backup includes:

- a transactionally consistent snapshot of `matedrive.sqlite`;
- encoded `AppSettings`, including display preferences, units, currency, pricing configuration, battery calibration, selected vehicle, and server configuration that is already stored outside Keychain.

Each backup excludes:

- API tokens, Basic Auth passwords, AK/SK secrets, and Cloudflare secrets from Keychain;
- HTTP response-cache files;
- dashboard, activity, widget, map, weather, image, and generated-share caches;
- diagnostics, temporary exports, and launch assets.

Keychain values use device-only accessibility and are never read by the backup service. After restoring on a new device, MateDrive may require the user to enter authentication secrets again.

## Consistent SQLite Snapshot

`SQLiteDatabase` gains a small online-backup wrapper around `sqlite3_backup_init`, `sqlite3_backup_step`, and `sqlite3_backup_finish`.

Backup creation copies the live database into a temporary SQLite file through the database actor. Actor isolation serializes the operation with MateDrive's other database work, and the SQLite backup API produces a consistent snapshot without copying an active database file directly.

After snapshot creation, MateDrive:

1. reads the schema version;
2. calculates SHA-256;
3. applies complete-file data protection to the temporary file;
4. creates the CloudKit asset and record;
5. uploads the record;
6. verifies that CloudKit returned a saved record;
7. removes the temporary local file.

Cancellation or failure removes any unfinished temporary file. The live database is never moved, renamed, or closed during backup.

## Automatic Backup Policy

Automatic backup is disabled by default. The user enables it from Settings after seeing that route, location, charging, and vehicle history may be included.

When enabled, automatic backup is eligible only when:

- a full background or foreground data synchronization completed successfully;
- no successful automatic backup has been uploaded in the previous 24 hours;
- an iCloud account is available;
- no backup or restore operation is already running;
- the background task has not expired or been cancelled.

The coordinator creates at most one automatic backup per 24-hour window. Manual backup is available when iCloud is available and ignores the 24-hour limit. The first manual backup requires the same explicit privacy disclosure used by the automatic-backup toggle; accepting a manual backup does not silently enable automatic backup.

The three newest successful backups are retained regardless of kind. Retention deletion runs only after a new record is saved successfully. A retention failure does not invalidate the new backup; the UI shows a nonblocking cleanup warning.

## Restore Flow

Restore is destructive and always requires confirmation. The confirmation states that current local MateDrive data and non-secret settings will be replaced, while Keychain credentials remain untouched.

The restore coordinator performs these steps:

1. wait for the app data-sync coordinator to become idle and prevent a new sync from starting;
2. fetch the selected CloudKit record and asset;
3. verify record fields, file size, SHA-256, backup-format support, and SQLite integrity;
4. reject a backup whose schema is newer than the installed app can understand;
5. create a local safety snapshot of the current database and settings;
6. copy the downloaded backup into the live SQLite connection with the online backup API in the reverse direction;
7. run all current database migrations;
8. restore sanitized settings without changing Keychain values or the local automatic-backup consent flag;
9. clear disposable response, dashboard, activity, and widget caches so they cannot disagree with the restored database;
10. reload widget timelines and publish one app-wide restore-completed event;
11. rebuild root view models from the restored state and allow synchronization again;
12. delete the temporary download and local safety file after the restored app state is healthy.

If any step after local replacement fails, the coordinator restores the safety snapshot and original settings before synchronization is released. A restore is reported as successful only after migrations and root-state reload complete.

The restore operation is serialized with database access by the existing SQLite actor. Pages remain covered by a blocking restore-progress surface so no view reads a partially restored state.

## Architecture

### `CloudBackupServicing`

Abstracts CloudKit account status, listing, upload, download, and deletion. `CloudKitBackupService` is the production implementation. Tests use an in-memory implementation and do not require an iCloud account.

### `DatabaseBackupProviding`

Creates, validates, restores, and rolls back SQLite snapshots. The production implementation uses the existing `LiveAppDatabaseProvider` and the new `SQLiteDatabase` online-backup methods.

### `CloudBackupCoordinator`

An actor that owns backup scheduling, retention, restore serialization, temporary-file cleanup, and high-level error mapping. It depends on the CloudKit service, database backup provider, settings store, cache-clear services, and data-sync coordinator through narrow protocols.

### `CloudBackupViewModel`

A main-actor view model exposes account status, consent, backup list, operation progress, last success, and localized errors. It never accesses CloudKit or SQLite directly.

The backup feature is independent from dashboard and feature-page view models. No page navigation triggers a backup check or CloudKit fetch.

## Settings UI

Settings adds an **iCloud Backup / iCloud 备份** navigation row near Privacy and Local Data. `CloudBackupView` contains:

- iCloud account availability;
- Automatic Backup toggle;
- Last Successful Backup;
- Back Up Now button;
- the three newest backup rows;
- Restore and Delete actions for each row;
- Delete All Cloud Backups;
- a privacy explanation;
- a reminder that server passwords and tokens are not backed up.

The list loads only when the user opens this page. Cached backup metadata is shown immediately, and CloudKit refresh happens in the background. Backup and restore buttons have explicit progress states and cannot be triggered twice.

After a restore on a device without the required secret, Settings highlights Server and Authentication and explains that credentials must be entered again.

## Privacy And Security

- Cloud backup is opt-in and can be disabled at any time.
- Backup records use only the user's CloudKit private database and count against the user's iCloud storage quota.
- The database asset and settings field are encrypted by CloudKit.
- Temporary files use complete-file data protection and are deleted after use.
- No backup data is sent to a MateDrive-operated server.
- Keychain secrets are never included.
- Users can list and delete all cloud backups from the app.
- Privacy and Local Data, the support privacy page, App Store privacy text, and release documentation are updated before submission.

If the user signs out of iCloud or changes accounts, automatic backup pauses. Existing local MateDrive data continues to work. The app never deletes local data because iCloud is unavailable.

## Capabilities And Release Configuration

The app target gains the CloudKit capability and these entitlements:

- `com.apple.developer.icloud-services` with `CloudKit`;
- `com.apple.developer.icloud-container-identifiers` with `iCloud.com.matedrive.ios`.

`project.yml`, the generated Xcode project, the app entitlement file, App Store release audit, and submission checklist are updated together. The widget does not receive CloudKit entitlement because it reads restored data through the existing App Group snapshot.

The App ID and provisioning profiles must include the iCloud container. Development-device testing uses the development CloudKit environment. TestFlight and App Store builds use the production environment after schema deployment.

## Error Handling

User-facing states distinguish:

- no iCloud account;
- iCloud temporarily unavailable;
- network unavailable;
- iCloud quota exceeded;
- backup cancelled or background time expired;
- incompatible backup format or newer database schema;
- checksum or SQLite integrity failure;
- CloudKit rate limiting or service failure;
- restore rollback completed after failure;
- restore rollback failure requiring support.

Retryable CloudKit errors honor `CKErrorRetryAfterKey`. Automatic backup does not retry in a tight loop; it waits for the next eligible synchronization or the server-provided retry time. Manual operations retain an explicit Retry action.

## Verification

Automated tests cover:

- SQLite online backup producing a consistent snapshot during writes;
- snapshot checksum and integrity verification;
- Keychain secrets never entering records or temporary files;
- sanitized settings encode and restore;
- automatic-backup consent and 24-hour eligibility;
- cancellation and expiration cleanup;
- three-record retention after successful upload only;
- iCloud account and quota error mapping;
- restore compatibility rejection;
- restore migration;
- restore cache invalidation and root reload;
- rollback after every restore failure stage;
- backup-list cached-first behavior;
- English and Simplified Chinese localization coverage;
- entitlement, privacy-document, and release-checklist audits.

Manual tests use a physical iPhone signed into iCloud:

- enable automatic backup and create a manual backup;
- verify record date, type, version, and size;
- relaunch offline and confirm local behavior is unchanged;
- restore the backup after changing local data;
- install on another device using the same Apple Account and restore;
- confirm credentials are requested again when absent;
- simulate iCloud sign-out, network loss, quota failure, cancellation, and app backgrounding;
- delete one backup and all backups;
- verify the widget and every cached-first feature after restore;
- verify TestFlight against the production CloudKit schema.

The full MateDrive test suite and App Store release audit must pass before distribution.

## References

- [Apple: CloudKit private database](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)
- [Apple: Encrypting user data in CloudKit](https://developer.apple.com/documentation/cloudkit/encrypting-user-data)
- [Apple: CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)
- [SQLite: Online Backup API](https://www.sqlite.org/backup.html)
