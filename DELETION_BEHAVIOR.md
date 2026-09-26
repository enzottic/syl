# Deletion behavior (issue #130)

## Implementation plan

1. Set a persistent deletion-pending marker and revoke the requested sync setting before changing the local store. The marker prevents any app or extension that opens the shared store after that point from enabling CloudKit mirroring.
2. Delete the local export and SwiftData records, remove local preferences, explicitly remove Syl's iCloud key-value-store keys even if ordinary sync is off, and send a zero-valued Watch snapshot. Keep the app on a restart screen after the local step so it cannot create new data before the cloud step.
3. On the next launch, before SwiftData opens the store, use Core Data's `purgeObjectsAndRecordsInZone` for Syl's private mirror zone. Repeat the export and preference cleanup so a crash during step 2 is recoverable. Clear the pending marker and return to onboarding only after the purge and KVS synchronization request succeed.
4. If the cloud step fails, keep the marker, leave sync disabled, and show a retry screen. Do not claim cloud deletion has completed.
5. Validate with two devices and a real iCloud account before release. Unit tests cover local state, consent, KVS access, and retry gating; they cannot prove cloud propagation.

The direct `CKDatabase.deleteRecordZone` API is deliberately not used while SwiftData mirrors the same store. Apple's [CloudKit container documentation](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/purgeobjectsandrecordsinzonewithid%3Ainpersistentstore%3Acompletion%3A) provides the managed purge operation, and [Apple's forum guidance](https://developer.apple.com/forums/thread/809726) notes that an out-of-band zone deletion can be recreated by the default store.

## What happens in each scenario

| Action and effective expense-sync state | On this iPhone | iCloud and other devices | Next launch or retry |
| --- | --- | --- | --- |
| Delete Expenses Only, mirroring active when Syl opened | Expenses are removed; recurring rules may create new ones. | SwiftData queues deletions for CloudKit. Other devices change after import; export is asynchronous. | The requested sync toggle takes effect for expense mirroring only after relaunch. |
| Delete Expenses and Recurring Rules, mirroring active | Expenses and rules are removed. | SwiftData queues both deletions; other devices update after import. | Same launch-time mirroring rule. |
| Either expense-only action, mirroring inactive when Syl opened | Selected records are removed locally. | Existing cloud copies remain. Whether an offline deletion is exported or old data is reimported after opt-in still requires a two-device test. | Re-enabling sync may restore old cloud records. These actions do not clear the cloud zone. |
| Delete All Data, sync requested on and mirroring active | Records, settings, and Syl's local CSV export are removed. KVS keys are removed and a blank Watch snapshot is submitted. | Existing mirror work may continue until the process exits. The cloud purge is pending. Other devices can still show old data. | Syl opens the recovery screen before SwiftData; the Core Data purge removes the private mirror zone and local mirror objects. On success, onboarding appears. |
| Delete All Data, sync requested off and mirroring inactive | The same local cleanup occurs. Explicit user deletion still accesses KVS. | The cloud purge remains pending even though ordinary sync was off, so old cloud data cannot be imported by enabling sync. | The same pre-SwiftData purge runs on relaunch. |
| Sync toggle changed during the current session | Delete All Data still sets the pending marker and requested sync to off. | Expense mirroring continues according to the state at launch until quit. | The pending marker forces mirroring off at the next launch. |
| iCloud unavailable or purge fails | Local cleanup remains. The Watch context may still be awaiting delivery. | Cloud data may remain; no cloud-success claim is made. | A retry screen blocks normal use and sync until the purge succeeds. |
| Local deletion fails before the cloud step | The model transaction rolls back where possible. The CSV may already have been removed. | No cloud purge has run. | Previous pending and requested-sync states are restored for that attempt. |
| App exits mid-deletion | The marker remains if local deletion had started. | Cloud data may remain. | Recovery repeats local export/settings cleanup and purges the mirror before normal startup. |
| User saved or shared a copy outside Syl | The external copy is untouched. | Syl cannot delete that copy. | It must be removed separately. |

WatchConnectivity delivery and KVS propagation are asynchronous. A successful KVS `synchronize()` call is not confirmation that another device has received removed keys. The acceptance criterion about old data not returning must be checked on two devices, including one that was offline during deletion.

## Release verification on devices

1. On two signed-in devices, enable sync, create an expense, rule, tag, nondefault income, allocation, currency, and setup state. Wait for both devices to show the same values.
2. Delete All Data on device A with sync on. Confirm the local restart screen, then fully quit and reopen A while online. Confirm onboarding appears and CloudKit's private mirror zone is empty or absent. Let B receive changes, then relaunch B and verify no old records or settings return. Re-enable sync on A and verify it stays empty.
3. Recreate the data. Fully quit A, turn sync off, relaunch A so expense mirroring is inactive, and repeat deletion. Confirm the same cloud and re-enable behavior.
4. Repeat with B offline during A's deletion; reconnect B only after A reports completion. Check that B does not recreate the old zone or send old settings back.
5. Repeat with A offline during the relaunch purge. Confirm the retry screen, blocked sync and expense entry, then reconnect and retry. Check the Watch receives an empty summary and A returns to onboarding only after completion.

These device checks are required because SwiftData mirroring, KVS delivery, and WatchConnectivity cannot be confirmed by in-memory unit tests.
