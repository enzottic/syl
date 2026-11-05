# Cloud synchronization redesign

Revised October 29, 2026. Design only; application code is unchanged. This replaces the earlier proposal for user-managed local and iCloud libraries.

**One toggle, automatic reconciliation, visible status.**

The user sees one library, a **Sync with iCloud** toggle, and a status underneath. Turning the toggle off stops new synchronization work on this device. Turning it on resumes synchronization and automatically reconciles local changes. No library picker, recovery-copy workflow, or manual import is part of normal use.

The intended behavior follows the user's observations of Crouton. Its [website](https://crouton.app/) confirms iCloud synchronization, but does not document this precise deletion/edit policy or its implementation. Treat the observations as Syl's requested behavior, not proof of Crouton's internal architecture.

| While sync is off | After sync is enabled again |
| --- | --- |
| No local change | Bring in changes from iCloud |
| Add an expense | Keep it and upload it |
| Edit an expense | Keep the edited values and upload those changes |
| Delete an expense that remains in iCloud | Restore it; do not send the local deletion to iCloud |
| Add, then delete a new expense | Leave it absent; nothing to upload |
| Edit, then delete an existing expense | Restore the iCloud-library version; the deleted local item contributes no edit |

While sync is on, normal deletions propagate to other devices. Merely losing the network while the toggle remains on is different: those deletions still synchronize when connectivity returns.

Suggested footer: “When off, changes stay on this device. Turning sync on uploads additions and edits and restores items that still exist in iCloud.” It describes the unusual deletion rule without asking the user to make another choice. Already-submitted operations may finish after disabling; the app cannot recall an upload already accepted by the system.

**Recommended implementation for this codebase.**

Keep SwiftData's managed CloudKit transport. Use two internal stores, with only one presented to the app at a time:

- The existing `Sage.sqlite` retains its CloudKit identity and history.
- A temporary device-only working store uses `.none` while sync is disabled.

These are implementation details, not two user-facing libraries. On re-enable, automatically apply additions and edits from the working store to the retained mirrored store, and do not propagate missing rows as deletions. Then rebuild the active container and return to ordinary managed synchronization. After a durable successful handoff, discard the temporary copy and baseline. Keep them only when needed to recover an interrupted or failed switch.

A one-store configuration flip is shorter, but does not provide the requested deletion behavior. Apple describes managed mirroring as exporting persistent history; its engineer guidance explicitly preserves history so disabled stores can catch up later. Do not try to remove selected transactions or CloudKit metadata to suppress deletions. [Apple synchronization overview](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer), [Apple engineer guidance](https://developer.apple.com/forums/thread/118924).

A one-store alternative would represent off-mode deletions as device-local hiding. That requires filtering those records out of every query, aggregate, relationship, export, reminder and recurring generator. This checkout has direct `@Query`, fetch and deletion access throughout those features. A narrow store-copy/merge boundary is preferable to spreading special deletion semantics across them. This is an engineering judgment based on the current code, not a claim that two stores always require fewer lines.

**Three responsibilities, using existing code where possible.**

1. Extend `SageModelContainer` to construct a specified store with explicit CloudKit configuration. Preserve Release `Sage.sqlite`, the existing schema/migration plan, and isolated Debug `SageDev.sqlite`. Read-only widget access must not run the existing write-producing backfill.
2. Add one observable database-session owner to replace the fixed `static let` container. It owns the active container, mode, generation and transition state. It coordinates rebuilding the SwiftUI subtree and services; app-only services remain in the app module.
3. Add a complete value snapshot and a small merge routine for the four model types. The existing expense-backup format is incomplete: it excludes accounts, unused tags and settings. Reuse suitable encoding helpers, but preserve all fields, UUIDs, relationships, recurrence state and ledger preferences.

No custom CloudKit engine, record mapper, third-party synchronization package or general conflict-resolution framework. Store construction uses Apple's documented [CloudKit configuration choices](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct).

**Turning off.**

Briefly gate writes, finish accepted pending edits, and stop app-owned recurring/import/reminder work and preference synchronization. Create a coherent value snapshot of the mirrored library and populate a fresh `.none` working store. Preserve the snapshot as the baseline for this off interval. A baseline and working copy must describe the same saved graph; account for imports racing the snapshot.

Detach the old data-bound SwiftUI subtree, release old contexts/services, activate the local container and recreate the subtree with a new generation. Commit the mode only when the local store is ready. Future changes, including deletions, affect only that working store. The retained mirrored file receives no off-mode application writes.

Do not copy a live SQLite file or its mirroring metadata. The local graph uses new model instances with the same domain UUIDs.

**Turning on.**

Save local work and compare the final working snapshot with the baseline:

- Rows absent from the baseline but present locally are additions.
- For rows present in both, record only fields that actually changed.
- Rows absent locally contribute no operation, even when they existed in the baseline.
- Unchanged rows contribute no operation; do not overwrite newer cloud data with the entire stale local snapshot.

Apply that delta to the retained mirrored store before restarting managed mirroring, using a `.none` maintenance container and one save. Update existing objects in place so their CloudKit identity survives. Resolve relationships in a second pass by domain UUID; copy required account/tag dependencies without interpreting a locally deleted related row as a remote deletion. Restart CloudKit only after releasing the maintenance container.

The retained mirrored cache already contains objects deleted only from the working copy, so those items reappear immediately where available. Further remote records arrive asynchronously. Do not destroy/reseed the mirrored cache or wait for a supposedly complete download. Empty fetch results and successful import events are not proof the entire server library is known.

A locally changed field wins against the retained cache during this handoff. This preserves an ordinary edit made while off. If another device concurrently edits or deletes the same item, managed CloudKit conflict behavior still applies. Do not promise unconditional local precedence against every later remote import. A requirement for deterministic global conflict precedence would require additional versioning/sync work and is outside this minimal design.

Apply the same diff principle to supported preferences: retain changed local keys, read unchanged keys from the cloud path, and do not interpret a local reset as a cloud-removal request. KVS delivery is separate from model mirroring. Capture changed values before restarting the existing read-on-start service so remote callbacks cannot overwrite them first. Currency and budget must stay coherent with the selected ledger.

**Failure recovery without extra user workflows.**

Persist a small transition record with the source mode, destination, baseline and phase. Make delta application repeatable by stable UUID and final field value. A crash after applying the delta but before committing cloud mode must not insert duplicate records on retry. Keep application edits blocked during reconciliation and preserve the local working store until handoff commits. Save failure leaves the toggle off; destination-open failure reopens the previous committed mode and reports an error.

Do not promise to roll back an upload after cloud mode starts. Delay all local additions/edits to the mirrored store until the user has requested enabling. Repeated switching must be verified on signed devices: SwiftData has no documented synchronous shutdown barrier, and sleeps are not a substitute for releasing old owners.

**Container consumers.**

Rebuilding the environment alone is insufficient. Replace the contexts retained by `ExpenseStore`, recurring-expense maintenance, reminder scheduler closures and data-bound navigation/sheets. Stop observers/tasks explicitly and reject stale callbacks with a session generation. Preserve safe value-only navigation so the user remains on the settings screen.

Register a stable session dependency at launch so shortcuts and entity queries resolve the current store per operation, including headless launches. Serialize writes through save against switching. Widgets read the committed active-store descriptor with fresh contexts and `.none`; refresh timelines after a switch or successful cloud import. Coordinate cross-process writes if target membership permits them; a shared preference flag is not a lock. Send the existing phone-generated Watch snapshot after each switch.

Keep the toggle device-specific and out of KVS. Gate `PreferenceSyncService` on both build capability and the active mode; otherwise preferences could continue uploading while expenses are local.

**Sync status.**

Reuse the Core Data CloudKit event stream already observed by `RecurringExpenseCoordinator`, with a small session-scoped status observer. Apple recommends `eventChangedNotification` to observe synchronization. [Apple troubleshooting guidance](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer).

| Display | Evidence |
| --- | --- |
| Off | Local mode committed |
| Switching… | Container transition or local reconciliation underway |
| Syncing… | Active setup/import/export event for this store |
| Waiting for iCloud | Enabled, but work has not completed or a retryable condition is reported |
| Last activity: time | Most recent successful completed import/export; no currently active event |
| Could not sync | Reported failure, with a useful account/storage/network explanation |

Track overlapping events by identifier rather than one boolean; filter by store/session and ignore old-generation callbacks. Keep preference failures separately identifiable. A successful import does not prove exports completed, and a successful export does not prove another device received the data. Prefer a factual activity timestamp over an unsupported “Everything is synced” guarantee. No invented progress percentage or network polling loop.

**Deletion, recurring work and migration.**

Off-mode expense deletion and full reset affect only the working store and local preferences. Clear the existing app-owned CSV as appropriate; external exports remain untouched. Preserve the mirrored store and baseline internally so re-enabling restores cloud items and never replays local deletion. The off-mode delete confirmation must state that iCloud data can return. On-mode deletion retains its asynchronous CloudKit behavior and cannot promise a purge of records not yet downloaded.

Recurring rules follow the same addition/edit/deletion rules. A rule deleted only locally can return and generate future expenses after re-enabling. Reconcile generated expenses by the existing occurrence identity and preserve generation progress; UUID matching alone cannot prevent independently generated duplicate occurrences. Reuse existing recurring repair logic and validate it against this transition.

Preserve the current enabled default for existing installs. A first-time local user has an empty baseline and their surviving local records become additions when enabling. Treat intentionally imported copies and records already synced on other devices carefully; domain UUID equality is not a CloudKit uniqueness guarantee, and late-arriving duplicates require existing import/repair policy rather than assuming a zero-row cache means an empty cloud library. Legacy stores containing off-mode deletion history need detection before reopening with CloudKit; separation cannot undo already-uploaded deletions.

**Focused validation.**

First validate repeated signed-device container replacement. Keep the seeded Debug database isolated; use a dedicated CloudKit test configuration. Then test only the changed merge/session/preferences/consumer code:

- Add, edit, delete, edit-then-delete, and add-then-delete while off.
- No change remotely while off; edits upload and locally deleted cloud items return on re-enable.
- Unchanged local fields do not overwrite newer remote values; concurrent same-item changes are characterized separately.
- Complete four-model snapshot and relationship round trip, including accounts and unused tags.
- Recurring occurrence deduplication and scheduler replacement.
- Failure/crash on either side of merge and mode commit; retry never duplicates additions.
- Shortcut, widget, reminder and Watch behavior after switching without app restart.
- Overlapping sync events, stale callbacks, account/quota failures and accurate status text.

Use focused unit tests and a two-device manual matrix. No full suite or UI-test suite. The remaining engineering risk is safe container teardown and reconciliation under real CloudKit timing, not the simplicity of the toggle UI.
