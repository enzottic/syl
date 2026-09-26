# Deletion behavior (issue #130)

## Implementation plan

1. Make the scope explicit in Settings: **Delete Data on This Device** clears Syl's local records, settings, and CSV export. It does not promise to delete the iCloud copy. Show the separate Apple Settings route for cloud deletion before and after the local action.
2. When local deletion starts, turn off the requested sync setting and set a persistent pending marker. The marker prevents Syl, widgets, and shortcuts from opening a newly mirrored store or adding records while the reset is unfinished. The current SwiftData container retains its launch-time mirroring setting until the process exits.
3. Delete local records and the export, reset local preferences, explicitly remove Syl's iCloud key-value-store (KVS) keys even when ordinary sync was off, and send an empty Watch snapshot. Ask the user to close Syl first, remove the cloud copy in iCloud Storage, then reopen Syl. Closing first prevents the still-active mirror from recreating cloud records during the Settings step.
4. On relaunch, open the store with mirroring disabled and clear local records and preferences again. This catches records the old session could have imported after the first deletion. Clear the pending marker and return to onboarding after local cleanup succeeds. Do not block the local reset on iCloud availability; if local cleanup fails, keep sync off and offer retry.
5. Verify the Settings path and two-device behavior with a production build and a real iCloud account before release. Unit tests cannot establish whether Apple's Storage action also removes KVS data or whether another device will upload an old local copy.

Apple documents [third-party iCloud storage deletion](https://support.apple.com/en-gb/guide/icloud/mm62d92d6b3e/icloud). [Goodnotes uses the same Settings flow](https://support.goodnotes.com/hc/en-us/articles/360004073756-Understand-Goodnotes-storage-sizes-on-iPad-and-iCloud) and notes that local documents can later be uploaded again. Syl clears its KVS keys itself because [KVS is a separate iCloud service](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore), and the Storage action is not a verified substitute for that API.

## What happens in each scenario

| Action and effective expense-sync state | This device | iCloud and other devices | Relaunch or later opt-in |
| --- | --- | --- | --- |
| Delete Expenses Only, mirroring active when Syl opened | Expenses are removed; recurring rules may create new ones. | SwiftData queues deletions for CloudKit. Other devices change after import; export is asynchronous. | The requested sync toggle takes effect for expense mirroring only after relaunch. |
| Delete Expenses and Recurring Rules, mirroring active | Expenses and rules are removed. | SwiftData queues both deletions; other devices update after import. | Same launch-time mirroring rule. |
| Either expense-only action, mirroring inactive when Syl opened | Selected records are removed locally. | Existing cloud copies remain. Whether an offline deletion is exported or old data is reimported after opt-in needs a two-device test. | Re-enabling sync may restore old cloud records. These actions do not clear the cloud copy. |
| Delete Data on This Device, mirroring active | Local records, settings, and Syl's CSV export are removed. KVS key removal and a blank Watch snapshot are submitted. Requested sync turns off and the pending marker blocks new writes. | The already-open mirror may still process changes until Syl exits. This action does not confirm cloud deletion. Another device can retain or re-upload data. | User closes Syl, deletes the iCloud copy in Apple Settings, then reopens Syl. Its store opens without mirroring and local cleanup repeats before onboarding. |
| Delete Data on This Device, mirroring inactive | Same local cleanup, including an explicit KVS removal request despite the sync toggle being off. | Cloud records remain until the user removes them in Apple Settings. | Relaunch repeats local cleanup. Re-enabling sync before removing the cloud copy can restore records. |
| Sync toggle changed during the current session | Local deletion still sets the pending marker and requested sync to off. | Expense mirroring continues according to the state at launch until exit. | The pending marker forces mirroring off on relaunch. |
| iCloud unavailable during local deletion | Local records and settings are removed. A KVS synchronization request may fail. | The cloud copy remains; remote preference removal is unconfirmed. | Local reset can finish. Use Apple Settings for the cloud copy once iCloud is available. |
| Local deletion fails | The model transaction rolls back where possible. The CSV may already have been removed. | No manual cloud deletion has occurred in this flow. | Previous pending and requested-sync states are restored for that attempt. |
| App exits mid-deletion | The marker remains if local deletion had started. | Cloud data may remain. | Recovery repeats local cleanup with mirroring disabled. |
| User deletes Syl data in iCloud Storage only | Local records on each device may remain. | Apple's Settings action removes the iCloud copy; local copies can be uploaded later. | Clear device copies before enabling sync again. |
| User saved or shared a copy outside Syl | The external copy is untouched. | Syl cannot delete that copy. | It must be removed separately. |

WatchConnectivity delivery and KVS propagation are asynchronous. A successful KVS `synchronize()` call is not confirmation that another device has received removed keys. The two-step flow requires the user to remove the cloud copy and handle other devices; Syl cannot promise that old data will never return merely because local deletion finished.

## Release verification on devices

1. On two signed-in devices, enable sync, create an expense, rule, tag, nondefault income, allocation, currency, and setup state. Wait for both devices to show the same values.
2. Delete device data on A while sync is on. Confirm the local instruction screen, KVS removal request, and blank Watch snapshot. Close Syl on A from the App Switcher. In Apple Settings, confirm Syl appears under iCloud Storage and that **Delete Data from iCloud** removes its cloud copy. Reopen A; confirm onboarding and no records.
3. Repeat with sync turned off before opening A. Confirm local cleanup still removes KVS keys and the Settings step still removes the cloud copy.
4. Repeat with B offline. Check whether B's existing local copy uploads after reconnecting. The UI must not promise a global wipe; document the steps needed on B before turning sync back on.
5. Interrupt A between the first deletion and relaunch. Confirm its pending marker prevents a newly mirrored store, shortcuts cannot add expenses, and recovery clears local data. Repeat with a KVS synchronization failure and verify local completion does not depend on iCloud.

These device checks are required because SwiftData mirroring, KVS delivery, Apple's Storage menu, and WatchConnectivity cannot be confirmed by in-memory unit tests.
