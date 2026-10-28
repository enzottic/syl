# Syl: expense capture and shared groups

**Date:** October 27, 2026

**Status:** Product and technical plan, based on the current working tree and current platform documentation.

## Recommended direction

Build a durable **expense inbox** that accepts local AI imports and purchase automations, and add **shared groups using CloudKit sharing**. Offer bank connectivity as an optional extension after validating coverage and cost.

Preferences established for this plan:

- AI parsing stays on-device.
- Friends need to collaborate: add expenses, see balances, and record settlements.
- iPhone-only collaboration is acceptable; friends can install Syl and use iCloud.
- Capture should cover Apple Pay taps and other US bank/card purchases.
- This pass produces an implementation plan.

| Problem | Recommended solution | Feasibility and dependency |
| --- | --- | --- |
| Bulk expense entry | Photos, PDF, CSV, and pasted text → local extraction → editable batch import | Feasible with existing Vision/Foundation Models components; measure accuracy and latency on a physical device |
| Splitting with friends | Shared group ledger, iCloud invitations, exact splits, settlements | Feasible with CloudKit sharing; requires a new shared-data layer and multi-account verification |
| Capture after paying | Wallet automation → a purpose-built capture action | Feasible; verify actual trigger data and locked-device execution |
| More US card purchases without an API subscription | On iOS 27, pilot bank-notification automations feeding the same inbox | Promising; coverage depends on each bank's alerts, available notification text, and automation behavior |
| Complete bank transaction history and reconciliation | Optional supported-bank connector | FinanceKit does not cover general US cards; broader aggregators have costs and refresh delays |
| MCP access | An adapter to a versioned import format and the same intake service | Possible later; a desktop client needs an explicit handoff to the iPhone |

## 1. What the code already provides

| Existing component | Finding | Consequence for this work |
| --- | --- | --- |
| [ExpenseCSVCodec.swift](FinanceTracker/Core/DataManagement/ExpenseCSVCodec.swift#L89) | Accepts Syl's exact six/seven-column CSV formats | Bank CSV needs column/sign/date mapping; arbitrary statements cannot be imported directly |
| [ExpenseImportService.swift](FinanceTracker/Core/DataManagement/ExpenseImportService.swift#L175) | Has staged validation, save-time rechecking, cancellation, and rollback | Reuse its transactional approach for reviewed batch commits |
| [ExpenseImportService.swift](FinanceTracker/Core/DataManagement/ExpenseImportService.swift#L154) | Every CSV row appends; backup deduplication uses existing IDs/recurrence keys | New capture/import sources need persistent source identities and matching |
| [ExpenseBackupService.swift](FinanceTracker/Core/DataManagement/ExpenseBackupService.swift#L27) | JSON input is interpreted as a Syl backup | Define a separate, versioned expense-import format for automation/MCP |
| [ExpenseBackupSettingsSection.swift](FinanceTracker/Features/Settings/Backup/ExpenseBackupSettingsSection.swift#L291) | Review shows counts and tag decisions | Add transaction-level editing and selection in a prominent import flow |
| [ReceiptParserService.swift](FinanceTracker/Core/Receipts/ReceiptParserService.swift#L17) | Parses one image into one expense; iOS 26 uses Vision then Foundation Models | Extract reusable text processing and add a bounded batch coordinator |
| [ReceiptParserService.swift](FinanceTracker/Core/Receipts/ReceiptParserService.swift#L160) | The amount guide suggests choosing the highest price; output has no currency | Correct extraction semantics before using the parser for statements, tender/change, or foreign-currency receipts |
| [AddExpenseIntent.swift](SageKit/AppIntents/Intents/AddExpenseIntent.swift#L12) | Requires authentication, a name, a currency-valued amount, and a category | These are potential automation friction points; reproduce the user's failure before assigning a root cause |
| [AddExpenseIntent.swift](SageKit/AppIntents/Intents/AddExpenseIntent.swift#L46) | Deliberately interprets the numeric amount in the ledger currency | New external capture must retain the source currency and resolve mismatches |
| [ExpenseStore.swift](SageKit/Persistence/ExpenseStore.swift#L65) | Shortcut writes use an isolated context | Preserve this behavior so automated writes do not commit an open editor's pending changes |
| [SageApp.swift](FinanceTracker/App/SageApp.swift#L39) | Registers the intent dependency only when storage opens successfully | Capture needs a resolvable service that reports storage failure clearly |
| [SageModelContainer.swift](SageKit/Persistence/SageModelContainer.swift#L106) | Release supports private iCloud sync; Debug uses a local development store | Syl already has private sync infrastructure; shared groups require additional sharing support |
| [SageSchemaV9.swift](SageKit/Schema/SageSchemaV9.swift#L9) | Expense/account models lack import provenance and split participants/allocations | Add versioned intake/link metadata and a shared-expense domain model |
| [Expense+Totals.swift](SageKit/Models/Expense+Totals.swift#L5) | Budgets aggregate each expense's amount | The personal ledger must represent the user's own share consistently |

The former Splitwise integration was removed in commit `0eec4c2`. The replacement needs its own group ledger and synchronization.

### Existing product patterns to carry forward

- YNAB's transaction review/matching flow demonstrates combining manual entries, file imports, and bank imports while retaining the ability to match and unmatch.
- Splitwise's group expense history, balance summary, and separate settlement records provide a familiar interaction model. Debt simplification is an optional later feature because it changes who pays whom even when net balances stay constant.
- Retain Syl's native SwiftUI navigation, semantic colors, system pickers, and existing monetary validation. Detailed screen layouts should be validated during implementation in light/dark mode, large text, and full navigation flows.

## 2. Shared foundation: the expense inbox

```text
Photos / PDF / text ── local extraction ─┐
Bank CSV ──────────── mapped parsing ───┤
Wallet automation ─── structured input ├─→ durable inbox → validate / match → personal expenses
Bank alerts ───────── captured text ────┤                                ↘ split with group
Future bank / MCP ─── source adapter ───┘
```

### User experience

- Put **Import Expenses** in the Expenses flow, alongside manual entry.
- Show an **Inbox · N to review** entry on Home and Expenses when there is work to do.
- Import opens a self-contained flow: choose source → see results arrive → edit/select → **Add N Expenses**.
- Review rows show merchant/name, amount, date, category, and source. A tap opens the original excerpt/image alongside editable details.
- Use actionable states such as **Ready**, **Needs details**, **Possible match**, and **Could not read**. Explain the field that needs attention.
- Completed rows remain available when a later file fails. Pausing or leaving the flow preserves completed parsing and selections.
- Complete, validated automation inputs can be auto-added using an explicitly configured rule. Missing fields and unresolved matches remain in the inbox. Keep the recurring daily experience short.
- Settings → **Automatic Capture** shows setup instructions, a test action, and the last event Syl actually received. A successful test is evidence of that execution; it cannot establish that every future trigger will run.

### Intake contract and persistence

Proposed domain types: `ExpenseIntakeBatch`, `ExpenseCandidate`, and `ExpenseSourceLink`. These are new application types, not existing Apple APIs.

Each candidate needs:

- A stable local ID allocated before inference, batch ID, source kind, and capture time.
- Provider/account/transaction IDs when supplied by a source.
- Original monetary text, parsed exact amount, ISO currency, and expense/refund/transfer classification.
- Transaction date separately from capture time, including whether the source supplied a time or only a calendar date.
- Proposed name/category/tags, missing-field reasons, and a reference to its original source/page/row.
- Review state and the resulting personal expense ID when committed.

Use `Decimal` or integer minor units for parsing and split arithmetic. Convert to the existing `Expense.amount` representation only after validating currency precision. Preserve debit/credit signs and distinguish refunds from card repayments or transfers.

Store raw intake material and resumable drafts locally in the app group. Persist the committed source link with the expense in the same ledger transaction. If saving succeeds before the inbox status updates, recovery uses that link to mark the item completed rather than inserting another expense.

### Matching rules

1. An existing provider/account/transaction ID is an exact source match.
2. Reopening the same document can reuse its document digest and persisted page/row identities. A document digest alone is not a cross-statement transaction ID.
3. Merchant/amount/date/card similarity produces a **possible match**. Two identical coffees can be two real purchases.
4. Wallet capture followed by a bank statement should reconcile with the original purchase. Bank posting dates and final amounts can differ because of tips, holds, or adjustments.
5. Imports and captures share matching behavior. Exclude explicitly dismissed source IDs from routine re-import, with a way to restore them.

Capture actions should also accept a caller-supplied event ID that remains stable across retries of that event. Wallet may supply no durable bank transaction ID; separate automation runs cannot always be distinguished from two genuine purchases. Keep those cases reviewable rather than promising exact deduplication from a time/amount fingerprint.

## 3. Track A — on-device bulk import

### Input paths

| Input | Extraction strategy |
| --- | --- |
| Syl CSV / structured import | Deterministic decoding and validation |
| Bank CSV | Preview and save column/date/sign mappings; use local AI only for ambiguous mapping or categorization |
| Text PDF | Read its text layer first and preserve page/row provenance |
| Scanned PDF / receipt images | Downsample appropriately, run Vision OCR, then extract transaction details locally |
| Pasted statements or receipts | Segment the supplied text and extract multiple candidates |

Treat a receipt as one purchase unless the user requests itemization. Treat a statement as multiple transactions, preserving continuation rows and page context. Statement balances, payment-due amounts, subtotals, cash tendered, and change are not separate purchases.

### Performance approach

1. Prewarm the first model session while the person is choosing input, leaving time for prewarming to help.
2. Use compact structured output and short extraction instructions. Avoid generating prose that the UI will discard.
3. Parse known structured data without an LLM. Reuse existing merchant/category decisions when applicable.
4. Process bounded chunks that leave room for instructions, schema, and output. Use fresh sessions per chunk; support the iOS 26 model's documented context limit and inspect newer model capabilities where available.
5. Keep one generation request active per session. Bound OCR/file work as well; large parallel batches can increase memory pressure and contention.
6. Publish completed, validated candidates progressively. Partially generated values can be shown as provisional, but only completed records become importable.
7. Checkpoint source positions and completed candidates. Foreground processing can resume after interruption without regenerating every completed document.
8. Preserve cancellation and specific errors. The existing parser currently replaces its own `noReceipt` error with `parsingFailed`.

When Apple Intelligence is unavailable, retain structured file import and manual correction. Show the actual availability reason rather than making the import feature disappear.

### Benchmark before setting speed promises

Use the slowest supported Apple Intelligence-capable iPhone and the user's own device, in a release build. Include approximately 10 varied receipts, a 100-transaction statement, a large CSV, a scanned PDF, and malformed/ambiguous inputs.

Measure cold/warm time to first reviewable row, total batch time, OCR versus generation time, peak memory, correction rate, missed/extra transactions, and cancellation/resume behavior. The source review establishes feasibility; no model latency or extraction-accuracy benchmark has been run for this plan.

### Completion criteria

- Import multiple receipts and a statement in one session, with editable per-row results.
- Reopening a completed batch does not duplicate its expenses.
- Missing date/currency and ambiguous totals remain visible for correction.
- One bad file does not discard other completed candidates.
- Cancellation before the commit rolls back the selected batch. Once the commit succeeds, report it as saved. Resuming parsing preserves prior work.
- The UI stays responsive, and results are verified against the benchmark corpus.

## 4. Track B — collaborative groups without Splitwise

### Product flow

1. Open **Groups** from Home or Expenses; create a named group with a currency.
2. Invite friends through the system iCloud sharing interface.
3. Add a group expense, or choose **Split with Group** on an existing purchase.
4. Default to an equal split among selected members. Allow exact custom amounts in the first release.
5. Show group history, **You owe / You are owed**, and a per-person breakdown.
6. **Record Settlement** records a full or partial repayment. It records a payment made elsewhere; no money movement is implied.

Group details are a pushed destination. Expense creation and settlement entry are contained modal tasks; member selection uses a short picker. After saving, return to the relevant group or purchase. Invitations opened from outside Syl should land on the group with a usable navigation stack after app setup.

### Storage and synchronization

Use **CloudKit `CKShare` with a custom record zone per group**. The owner accesses that zone through their private database; invited members access it through their shared database. All participants need an active iCloud account.

SwiftData's built-in CloudKit configuration exposes automatic/private/none options, so the current private-sync setting cannot supply multi-user sharing. Add a group repository using CloudKit APIs, a local cache/outbox, and `CKSyncEngine` for owned/shared group data. Explicitly scope it to Syl's group zones; SwiftData continues to own its managed zones.

Required integration work:

- Add share support and share-invitation acceptance to the app lifecycle, including cold launch and onboarding.
- Persist synchronization state and local outgoing edits; display **Saved on this iPhone / Syncing / Synced / Needs attention** accurately.
- Use stable group, member, expense, and settlement IDs. Associate members with their CloudKit identity, independently of their display name.
- Save an expense and its allocations atomically within its group zone. Detect concurrent edits using record revisions and reconcile explicitly.
- Handle membership changes, revoked shares, account changes, and offline operation. Preserve a user's already-recorded personal share as a local snapshot if shared access disappears.
- Use a CloudKit-enabled test configuration and two distinct iCloud accounts. The current Debug personal store is deliberately local-only.

This avoids a Splitwise subscription and a custom account server. Shared records count toward the originating owner's iCloud storage quota.

### Money and ledger semantics

Proposed shared records:

- `ExpenseGroup`: identity, name, currency.
- `GroupMember`: identity, display name, participant mapping.
- `SharedExpense`: identity, description, date, gross amount, payer, revision.
- `ExpenseAllocation`: member and exact owed amount.
- `Settlement`: sender, recipient, exact amount, date, revision.

For an equal split, distribute remainder minor units in a stable member order. For example, USD 10.00 across three members becomes 3.34 + 3.33 + 3.33. Validate that allocations equal the gross amount. Compute balances from expenses and settlements; AI is unnecessary for this arithmetic.

**Recommended budget behavior:** count the user's own share. For a USD 90 dinner paid by you and split three ways:

- Original purchase / cash paid: USD 90.
- Your personal expense: USD 30.
- Amount owed to you: USD 60.
- Later repayments reduce the receivable and do not add spending or negative spending.

Keep the gross source transaction and group allocations separately from the personal expense projection. Link the personal expense using a stable group-expense/member identity. Splitting an already-imported USD 90 purchase updates its personal projection to USD 30 while retaining the original USD 90 for bank matching and detail display. If a friend paid, your USD 30 share can still appear in your spending without fabricating a card transaction.

Category and tags remain the individual's personal classification. Start with one currency per group and require the ledger currency to match for automatic personal projection. A future foreign-currency workflow must record the actual conversion explicitly.

Include source/group links in versioned backups so restoring a personal ledger retains matching identities. A backup of personal projections does not recreate iCloud invitations or shared permissions.

### Completion criteria

- Two different Apple IDs can join, add/edit expenses, see converged balances, and record partial settlements.
- An offline edit survives relaunch and syncs when service returns.
- Simultaneous edits produce an explicit reconciled outcome and valid allocations.
- The USD 90 example gives USD 30 personal spending on each participant's ledger, including after reconnect/re-import.
- Remainder splits, refunds, deletion, settlement edits, and member removal keep balances correct.
- Home, Stats, tags, widgets, Watch summaries, and backups agree on personal spending.

## 5. Track C — automatic purchase capture

### C1. Purpose-built Wallet capture action

Add a new **Capture Purchase** action with numeric amount, currency code, merchant, date, and optional card/source ID. Missing transaction properties should be representable so the action can retain an incomplete event without prompting for a category. It should quickly enqueue the event and return a capture status.

Use an append-only background capture action with `.alwaysAllowed` authentication policy for locked-device capture, and verify that the intake storage is available in that execution context. Keep reads of the financial ledger out of its returned result. A system automation setting alone cannot override the existing intent's authentication policy.

Preserve the shipped `AddExpenseAppIntent` identifier and parameter contract for existing shortcuts. Give the new action clear parameter summaries and descriptions, and use user-visible App Intents errors for storage/setup failures. Refresh affected app/widget/Watch data after successful commits.

Offer a guided setup with a test event and version-appropriate instructions:

- **iOS 26:** create a Wallet/Transaction personal automation, select cards, enable immediate execution, and map transaction properties into the action.
- **iOS 27:** add the automation in the shortcut editor; explain the shortcut's enabled/locked-execution settings using the current UI.
- Publish a tested shortcut template after validating it on the supported versions. The user configures/enables the system automation in Shortcuts.

Wallet capture is an early purchase signal. It may lack an amount or a final posted amount, and it does not provide a general feed of physical-card and online transactions.

### Troubleshoot the existing Shortcut before implementation

1. Open the intended Syl installation and complete currency setup. Debug and Release have different bundle IDs/stores but both currently display the name **Syl**; verify which installation owns the action.
2. While unlocked, manually run **Add New Expense** with a recognizable name, a small fixed amount in the ledger currency, and an explicitly selected category. Confirm it appears in that same installation.
3. If the fixed-value action fails, capture its exact error first. Check currency setup and storage/dependency initialization before investigating Wallet.
4. Create a Transaction automation for one card. First inspect the received transaction's Merchant and Amount properties during a real iPhone tap.
5. Map **Shortcut Input → Merchant** to Name and **Shortcut Input → Amount** to Amount. Use the individual properties rather than the whole transaction object. If the numeric value fails to bind to the current currency-valued field, record the conversion error; the proposed Number-based capture action addresses that boundary.
6. Explicitly set the existing action's Category, avoiding an interactive category choice. Configure **Run Immediately**, or the version's equivalent **Ask Before Running** setting.
7. Repeat with the app backgrounded and the phone locked. The current `.requiresAuthentication` policy can require authentication even when the automation is configured to run automatically.
8. Check the intended app's expense list as well as its widgets. The current intent save path does not explicitly reload widget timelines, so a stale widget alone is not proof the write failed.
9. Test Watch-originated payments separately if used; do not infer their behavior from an iPhone tap.

These steps isolate app saving, trigger delivery, property conversion, and authentication. The user's actual shortcut failure has not yet been reproduced.

### C2. Bank alerts on iOS 27

Apple added a notification automation trigger that can target an app and filter notification text. Prototype a workflow for one of the user's actual banks:

```text
Bank purchase notification → Shortcuts notification trigger → capture supplied text → local parsing / rules → inbox
```

The first prototype should establish which title/subtitle/body properties are available, whether meaningful purchase details arrive while locked, and how the automation behaves with previews hidden or delayed notifications. The current general Apple Support automatic-trigger list does not fully document the new notification case, so end-to-end behavior needs verification.

Use deterministic rules for a known bank alert format. Queue ambiguous text for on-device extraction during an active import session. Alert capture can cover physical-card and online purchases that generate alerts, but it cannot reconstruct missed history or guarantee every final posted transaction. Reconcile against later statement imports.

### C3. Complete bank imports: coverage and cost

| Option | Fit for this app |
| --- | --- |
| FinanceKit | Apple's current US coverage is Apple Card, Apple Cash, and Savings. It does not solve the selected general-US-bank requirement. It also requires Apple's entitlement approval. |
| Bank notifications + local statement import | No aggregator subscription; capture is conditional on alerts, with statements filling gaps. Works with the chosen on-device parsing direction. |
| SimpleFIN Bridge | Optional bring-your-own bank connection. Currently USD 1.50/month or USD 15/year plus tax, up to 25 institutions and 25 apps. Institution support must be checked. Its developer guide describes daily updates, not immediate purchase notifications. |
| Plaid Transactions | Broader commercial integration candidate. Live use is metered/paid; sandbox and limited-production trials do not establish a permanently free bank feed. Adds backend/token/webhook work. |

Recommended order: Wallet capture → bank-alert pilot where available → statement reconciliation. Evaluate SimpleFIN if complete supported-bank imports justify its user subscription. A SimpleFIN adapter can use a user-authorized token stored in Keychain, refresh when the app can run, and feed the same intake contract. iOS background refresh and bank update schedules do not guarantee an immediate event for each purchase.

Exact institution names are still needed to select a bank connector. No bank account was connected or coverage verified for a particular institution in this assessment.

## 6. MCP compatibility

Local storage can accept external input through an explicit import interface. Build that interface once:

- A versioned structured batch format, with stable item IDs, decimal amount strings, currencies, source dates, and provenance.
- An App Intent to receive/stage a batch and an in-app route to review it.
- A result model reporting staged, added, matched, and invalid items.

A later desktop MCP server could prepare a batch file and hand it to Syl through Files or a user-selected synchronized folder. This is an asynchronous handoff; it needs Syl to receive/process the batch and an acknowledgement channel before the desktop can report that expenses were saved. Existing private CloudKit sync is not an MCP endpoint or an iCloud Drive folder.

An always-reachable MCP endpoint would require a running desktop companion or hosted relay because an iPhone app may be suspended. Defer that transport until the import contract works. On-device import remains useful independently of desktop AI clients.

## 7. Implementation sequence

| Milestone | Deliverable | Scope / dependencies | Exit evidence |
| --- | --- | --- | --- |
| 0. Feasibility probes | Reproduce Wallet input; benchmark local parsing; prove a two-account CloudKit share | Small focused prototypes; requires physical-device and iCloud access | Actual event payload/error, latency/accuracy measurements, shared write visible to the second account |
| 1. Inbox + Wallet | Durable candidates, source links, review UI, Capture Purchase, setup/test flow | Medium; shared foundation | Real purchase captured, restart survives, replay is handled without duplicate insertion |
| 2. Local bulk import | Multi-photo/PDF/text input, bank CSV mapping, progressive results, matching | Medium–large; milestone 1 | Corpus checks and successful edited batch import on device |
| 3. Broader alert capture | One supported bank-notification recipe, local parsing/rules, reconciliation | Small–medium; iOS 27 and milestones 1–2 | Actual alerts map correctly; behavior while locked and with missing text is documented |
| 4. Shared groups | Invitations, group repository/sync, split math, settlements, personal projections | Large; start the sharing repository after milestone 0, then integrate with intake | Two-account collaboration, offline/conflict behavior, correct budgets and backups |
| 5. Optional connectivity | Supported-bank adapter and/or desktop MCP handoff | Driven by remaining need and chosen provider | Verified institution coverage or acknowledged desktop-to-phone batch import |

### Implementation map

- **`SageKit/Intake/` (new):** candidate/source contracts, exact-value validation, persistence boundary available to App Intents.
- **`SageKit/AppIntents/Intents/`:** new capture/staging actions; keep existing intent identifiers stable.
- **`FinanceTracker/Core/DataManagement/`:** adapt reviewed intake commits and evolve backup/source-link support.
- **`FinanceTracker/Core/Receipts/`:** reuse OCR, correct receipt extraction, add text/PDF/batch processing.
- **`FinanceTracker/Features/ImportExpenses/` (new):** source selection and progressively populated review flow.
- **`FinanceTracker/Features/Settings/AutomaticCapture/` (new):** setup, diagnostics, last-received state.
- **`SageKit/SharedExpenses/` and `FinanceTracker/Core/SharedExpenses/` (new):** exact split domain logic, CloudKit repository, local cache, projections.
- **`FinanceTracker/Features/Groups/` (new):** group list/detail, expense splits, settlements, sharing UI.
- **`SageKit/Schema/`:** append a migration version for personal provenance/link metadata; provide local-only schemas for intake and group cache as needed.
- **`FinanceTracker/App/Navigation/` and app lifecycle:** import/group routes, invitation acceptance, capture dependency registration, data-change refreshes.
- **Existing test targets:** exercise money invariants, idempotent commits, interruption recovery, real Shortcuts handoff, and multi-account sharing. Simulator tests alone cannot verify actual Wallet events, model performance, or CloudKit collaboration.

## Sources

Platform and provider information checked October 27, 2026:

1. [Apple: FinanceKit availability and entitlement requirements](https://developer.apple.com/financekit/)
2. [Apple: Wallet transaction trigger, iOS 26](https://support.apple.com/guide/shortcuts/transaction-trigger-apd65c67538a/9.0/ios/26)
3. [Apple: Automatic execution settings, iOS 26](https://support.apple.com/guide/shortcuts/enable-or-disable-a-personal-automation-apd602971e63/9.0/ios/26)
4. [Apple: Add automations and locked execution, iOS 27](https://support.apple.com/guide/shortcuts/add-automations-apdfbdbd7123/10.0/ios/27)
5. [Apple WWDC26: What's new in Shortcuts — notification triggers](https://developer.apple.com/videos/play/wwdc2026/310/)
6. [Apple: Intent authentication policies](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy)
7. [Apple: Foundation Models context management](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)
8. [Apple: Foundation Models performance analysis](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app)
9. [Apple: Session prewarming](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm(promptprefix:))
10. [Apple: CKShare](https://developer.apple.com/documentation/cloudkit/ckshare)
11. [Apple: SwiftData CloudKit database options](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct)
12. [Apple: Shared database storage quota](https://developer.apple.com/documentation/cloudkit/ckdatabase/scope/shared)
13. [SimpleFIN Bridge pricing](https://beta-bridge.simplefin.org/) and [developer guide / refresh limits](https://beta-bridge.simplefin.org/info/developers)
14. [Plaid pricing](https://plaid.com/pricing/)
15. [YNAB: Approving and matching transactions](https://support.ynab.com/en_us/approving-and-matching-transactions-a-guide-ByYNZaQ1i)
16. [Splitwise: Group balances and debt simplification](https://feedback.splitwise.com/knowledgebase/articles/746853-my-dashboard-balances-are-different-than-my-group)
