# Syl release readiness audit

Reviewed October 9, 2026 against the working checkout, including its pre-existing uncommitted iCloud changes.

**Recommendation: do not submit this checkout yet.** There are confirmed data-consistency bugs, a reproduced bulk-deletion bug, inaccurate published privacy information, and unresolved verification of the new iCloud switching behavior. This audit is not an App Store approval or a certification of legal compliance.

Scope: source review of onboarding, expense entry/editing, Home, Stats, tags, settings, backups, recurring expenses, receipt import, notifications, persistence, App Intents, widgets, and Watch snapshots; selected simulator workflows and built-bundle inspection. The findings below remain open. This audit changed only two accessibility-test launch values and added this report; it preserved the existing in-progress app changes.

## Fix before release

### 1. P1 — Deletion confirmations overpromise what happens to iCloud data

Locations: [SettingsView.swift:156](FinanceTracker/Features/Settings/SettingsView.swift#L156), [AppConfiguration.swift:215](FinanceTracker/Core/Preferences/AppConfiguration.swift#L215), [PreferenceSyncService.swift:175](FinanceTracker/Core/Preferences/PreferenceSyncService.swift#L175).

The confirmation says deleting expenses and rules prevents their return, and Delete All Data describes permanent removal without distinguishing local and iCloud copies. With sync off, these operations cannot remove records already in iCloud; preference reset also returns without clearing cloud preferences. With sync on, full reset immediately disables sync after local deletion, triggering a container switch before any confirmed CloudKit deletion export. A local save and KVS `synchronize()` do not establish that cloud deletion completed.

Fix: make the scope explicit in both confirmations and success messages. Define and implement the sync-on/off reset behavior before promising permanent removal across devices. Keep deletion export and any recovery workflow compatible with that policy. Do not automatically purge CloudKit zones as a cosmetic fix. Real two-device verification is required; cloud resurrection/export behavior was not reproduced in this audit.

### 2. P1 — Stats clips valid spending, including refunds and overspending

Location: [StatsView.swift:236](FinanceTracker/Features/Stats/StatsView.swift#L236).

The Y-axis is always `0...max(monthlyIncome, 1)` and the plot is clipped. With income of 100 and spending of 150, the curve disappears above 100. With income zero, a 42.50 expense is plotted outside a 0–1 range. Negative cumulative spending from refunds is also outside the domain. Historical averages can be clipped too.

Fix: derive the domain from visible series, visible budget lines, historical averages, and zero, allowing negative values and padding. Hidden categories should not force the filtered chart's scale. Verify zero income, overspending, net refunds, category/tag filters, and a historical peak above the current total.

### 3. P1 — Monthly totals disagree across Home, Stats, widgets, and Watch

Locations: [MonthlyOverviewWidget.swift:21](FinanceTracker/Features/Dashboard/Cards/MonthlyOverviewWidget.swift#L21), [ExpenseStore.swift:184](SageKit/Persistence/ExpenseStore.swift#L184), [SpendingMonthSummary.swift:40](SageKit/Analytics/SpendingMonthSummary.swift#L40).

Expense entry permits future dates. Home and the iPhone monthly snapshot total the entire selected calendar month, whereas Stats and the Watch builder use `SpendingMonthSummary`, which excludes entries after the current time. Example: record 10 today and 100 tomorrow in the same month; Home/iPhone summary report 110 while Stats/Watch report 10. Siri monthly totals use the all-month path too. Home's comparison summary can disagree with its own main total.

Fix: adopt one shared definition of recorded spending across these surfaces. If future entries are intentionally included somewhere, label that total distinctly and keep budget calculations consistent. Test the boundary at today, tomorrow, and month rollover.

### 4. P1 — The published privacy policy is behind the app

Locations: [PrivacyWebView.swift:9](FinanceTracker/Features/Settings/Privacy/PrivacyWebView.swift#L9), [ReceiptPhotoLibrary.swift:23](FinanceTracker/Features/AddExpense/ReceiptAttachment/ReceiptPhotoLibrary.swift#L23), [local policy](PRIVACY_POLICY.md).

The live [privacy policy](https://getsyl.app/privacy) returned HTTP 200. Its September 24 version describes camera and notification permissions but omits the new Photos-library access, limited selection, and system-picker fallback already documented in the repository's September 25 policy. Both the published policy and the local policy still instruct people to restart to apply expense-sync changes; the working checkout now switches containers in-app.

Fix: reconcile the policy with the final shipping behavior, then publish it and verify the page from inside the app. Explain asynchronous cloud deletion accurately. This matters to the accuracy and privacy requirements in [Apple's guidelines, 2.3 and 5.1.1](https://developer.apple.com/app-store/review/guidelines/). The site was inspected but not modified or deployed.

### 5. P2 — Bulk deletion leaves unsaved records behind (reproduced)

Location: [DataDeletionService.swift:19](FinanceTracker/Core/DataManagement/DataDeletionService.swift#L19), also lines 51–55.

Both delete paths call `delete(model:)` before handling pending inserts, then save the context. Two isolated in-memory probes on iOS 26.5 reproduced surviving expenses after expense deletion, and surviving expenses and recurring rules after full reset. The seven existing deletion tests pass because their model fixtures are saved before deletion.

Fix: account for pending inserts before bulk deletion, preserving coherent rollback/error handling, and add regression coverage to the existing deletion tests. These are service-level reproductions; this audit did not reproduce a normal UI sequence that leaves those pending inserts at the moment of reset.

### 6. P2 — Delete All Data does not reset all app preferences

Locations: [AppConfiguration.swift:215](FinanceTracker/Core/Preferences/AppConfiguration.swift#L215), [StatsView.swift:12](FinanceTracker/Features/Stats/StatsView.swift#L12), [SageApp.swift:15](FinanceTracker/App/SageApp.swift#L15).

Reset clears the configuration's own keys but leaves `hasOpenedAppOnce` in standard defaults and the three `statsShows...Line` preferences. The app remains past onboarding with zero income and no default tags, and hidden chart-line choices survive an operation described as deleting all settings.

Fix: define a complete list of owned preferences, clear the applicable standard-default keys as well as shared preferences, and return to setup after successful reset. Preserve external export files as the current UI already explains.

## Other concrete bugs and polish

### 7. P2 — Apple Watch keeps stale values while the phone stays open

Location: [SageApp.swift:89](FinanceTracker/App/SageApp.swift#L89).

Watch snapshots are sent on active/background transitions only. Expense saves, edits, deletion, imports, budget changes, and completed CloudKit imports do not directly publish a Watch snapshot. A user can change or delete their records while leaving Syl in the foreground and continue to see the old Watch totals until a lifecycle transition and eventual transfer.

Fix: coalesce refreshes after committed data/preference changes, including reset, and verify on a paired device. Source-confirmed trigger gap; transfer timing was not measured on hardware.

### 8. P2 — Storage recovery leaves Shortcuts with an unregistered dependency

Location: [SageApp.swift:40](FinanceTracker/App/SageApp.swift#L40).

If `DatabaseManager` cannot open storage, `expenseStore` is nil and the App Intents dependency is never registered. Intents and entity queries still declare a required `@Dependency ExpenseStore`. Dependency resolution can trap instead of producing the recovery message shown in the main app.

Fix: register an always-available service that reports storage failure through a user-facing intent error, or provide an appropriate dependency fallback. Test a cold Shortcut invocation with forced storage-open failure. This failure path was identified from code and the App Intents dependency contract, not reproduced through Siri.

### 9. P2 — Find Expenses can report zero after a storage error

Locations: [ExpenseStore.swift:122](SageKit/Persistence/ExpenseStore.swift#L122), [FindExpensesIntent.swift:95](SageKit/AppIntents/Intents/FindExpensesIntent.swift#L95).

The date-range fetch converts every fetch error to an empty array. Find Expenses then returns a successful zero-spending answer, conflating a failed read with no matching records.

Fix: propagate storage errors to the intent and present a meaningful failure. Keep an actual empty result as a successful zero. Verify with an injected failed fetch.

### 10. P2 — An older AI suggestion can tag a newly renamed expense

Location: [ExpenseInfoForm.swift:281](FinanceTracker/Features/Expenses/ExpenseInfoForm.swift#L281).

The edit/recurring form launches an untracked asynchronous suggestion for `currentName`. On completion it only checks that tags remain empty. Rename the expense again while the suggestion is running and the first result can apply to the new name. The newer Add Expense flow already checks name equality and cancels stale tasks.

Fix: use cancellation and a name/revision check in the shared form too. Verify delayed responses, another name edit, manual tag selection, and dismissal.

### 11. P2 — Smart Tagging can have an invisible selected mode

Location: [TagsSettingsSection.swift:67](FinanceTracker/Features/Settings/Tags/TagsSettingsSection.swift#L67).

The picker removes AI modes when Apple Intelligence is unavailable, but the saved/synced selection can remain `.ai` or `.both`. Disable Apple Intelligence after selecting AI, or sync that setting to an unsupported device: the picker no longer contains the bound value and AI-only suggestions silently stop.

Fix: retain the selected unavailable option with an explanation, or visibly resolve to a supported fallback without silently overwriting a synced preference on other devices.

### 12. P2 — Tag buttons have undersized touch targets

Location: [TagPicker.swift:67](FinanceTracker/Features/Tags/TagPicker.swift#L67), including the Add button at line 81.

The plain buttons use a subheadline capsule plus 6 points of vertical padding per side, without a 44-point minimum hit frame. The visual capsule is approximately 32 points tall at the default text size. This is a touch-accessibility polish issue; it is not, by itself, a claim that App Review will reject the app.

Fix: keep the compact capsule appearance but give the button label a minimum 44-point hit area and content shape; verify wrapping and neighboring hit areas in the tag flow layout.

### 13. P3 — Receipt rejection loses its useful error message

Location: [ReceiptParserService.swift:56](FinanceTracker/Core/Receipts/ReceiptParserService.swift#L56), repeated at line 115.

Both parsing paths throw `noReceipt` inside a `do` block that immediately catches it and replaces it with `parsingFailed`. The intended instruction to choose a receipt is therefore unreachable for an AI-classified non-receipt.

Fix: preserve typed parser errors or move receipt validation after the model-call catch. Verify a receipt, an unrelated image, and a model failure separately.

### 14. P2 — Amount entry breaks words at the largest accessibility size

Location: [CentsFirstCurrencyField.swift:74](FinanceTracker/Shared/AmountEntry/CentsFirstCurrencyField.swift#L74).

With the corrected largest-text launch argument on iPhone 17 Pro Max, the horizontal transaction-type row renders “Transaction” and “Expense” split across lines inside the words. This was visually reproduced, even on the largest phone simulator. The buttons remain reachable; this is a readability/layout defect rather than a blocked workflow.

Fix: adapt this row to a vertical layout at accessibility sizes, giving the label and menu enough width without reducing the user's preferred text size. Inspect other narrow menu rows at the same setting. Screenshot evidence for this session: `/private/tmp/syl-release-audit-largest-text.png`.

### 15. P1 — Onboarding's Done button is covered by the keyboard at largest text

Location: [OnboardingView.swift:101](FinanceTracker/Features/Onboarding/OnboardingView.swift#L101), with the budget-page layout beginning at line 248.

The corrected largest-accessibility-text test fails after entering income: `onboarding-keyboard-done-button` exists but is not hittable. The recorded hierarchy places Done at y=748–825 points while the number-pad window occupies y=638–956 on a 440×956-point iPhone 17 Pro Max. Back/Continue also overlap the keyboard region. This is a product layout failure, unlike the iPad tab-selector failures. The previously invalid text-size argument concealed it.

Fix: ensure the budget content can shrink/scroll with the keyboard present and keep the footer within the keyboard-adjusted safe area, or provide an accessible keyboard toolbar dismissal action. Re-run this corrected test, then inspect the smallest supported phone and nonmonthly income selections. The test stops at this step, so the later onboarding pages at the true largest text size remain unverified.

## iCloud release gate

The working `DatabaseManager` opens a replacement container while `previousSession` still owns the old one. Both sync modes use the same `Sage.sqlite`. Stopping the app's reminder/recurring coordinators does not itself stop a CloudKit mirroring store. Treat the live-switch implementation as unverified until device tests establish the actual behavior; a successful simulator build is not sufficient evidence.

| Scenario | Current implementation / required verification |
|---|---|
| Sync off → delete expenses | Local records are deleted; existing iCloud copies are not explicitly deleted. Verify re-enable behavior and correct the confirmation. |
| Sync off → delete all | Local records/preferences are reset; cloud preference cleanup is skipped. Verify what returns on re-enable. |
| Sync on → delete expenses, keep sync on | Local deletion can export asynchronously. Verify another online device, then an offline device reconnecting. |
| Sync on → delete all | Reset turns sync off immediately. Verify deletion export, preference reset, and re-enable before claiming cloud erasure. |
| Switch on/off repeatedly | Verify old store/coordinator retirement, no duplicate mirroring errors, pending writes, and widget reads. |
| Local deletion → cloud recovery | No separate cloud-authoritative restoration workflow is implemented in the inspected same-file configuration. Establish the intended recovery policy before shipping. |
| Any reset with Apple Watch | Confirm a cleared snapshot reaches the Watch; it can retain an older snapshot until transfer. |
| Any reset with external backups | External files remain, intentionally. Existing copy explains this. |

Do not test destructive sync scenarios against a real personal ledger. Use disposable records and controlled test accounts/devices.

## Verification and App Store checks

- Release simulator build succeeded with Xcode 27.0 (27A266a), including the phone app, SageKit, iPhone widgets, Watch app, and Watch widget. This was an unsigned build, not an App Store archive validation.
- Three distinct concurrency warnings remain: the sheet controller completion closure at line 504, and two actor-isolation captures in onboarding's `visualEffect` at line 352. These were warnings, not build failures.
- Seven existing deletion tests passed on iPadOS 26.5. The two new temporary pending-insert probes failed as described above.
- iPhone backup export, native Files cancellation, JSON re-import with duplicate skipping, and CSV export/cancellation passed.
- The original four iPad UI checks failed: backup dismissal uses an iPhone-style swipe; three tests scope tab buttons to `app.tabBars`, while the iPad hierarchy exposes those buttons outside that container. The hierarchy contains Expenses and Stats. These failures do not establish broken product navigation. iPad onboarding reached the final step.
- Accessibility test launch arguments were found to contain an invalid hard-coded size value. The two affected tests were changed to use UIKit's actual `UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue`. The corrected expense-entry test passed; onboarding failed with its Done button behind the keyboard (finding 15).
- Camera and Photos purpose strings are specific and present in the built app. The app/SageKit/Watch manifests are bundled, with UserDefaults reasons and the phone app's active-keyboard reason. Third-party notices are bundled. No third-party package SDK dependency, ad SDK, external purchase flow, or account-registration service was found in the inspected project.
- Receipt processing uses Apple's on-device APIs and checks model availability. Reminders are optional, and the inspected notification UI has denied-permission recovery. Actual camera/limited-Photos/notification permission transitions and receipt quality still require physical-device checks.
- No obvious production TODO/coming-soon screen was found. Debug mock data and debug settings are conditionally compiled. The What's New catalog has only a 0.9.1 entry while the app version is 1.0; this produces no release-notes sheet, which is optional rather than a release blocker.

Before submission, verify the production CloudKit schema/container and entitlements, validate a signed archive in Organizer, and review App Store Connect's privacy answers, age-rating questionnaire, support/privacy URLs, screenshots, export-compliance answers, and review notes. Those account-side items were not accessible in this source audit. Describe receipt reading's Apple Intelligence/device/language requirements accurately in marketing and review notes.

Apple requires a complete, stable app and accurate metadata, and the privacy policy must describe the app's data handling. See [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) and [submission guidance](https://developer.apple.com/app-store/submitting/). Actual approval remains Apple's decision.

## Final focused rerun results

- Initial iPhone run: all four selected UI checks passed, including backup export/import and Stats month navigation. The two text-size tests in that run still used the invalid argument, so their passes did not validate the largest accessibility size.
- Corrected iPhone accessibility run: expense entry with a long name passed; onboarding failed after income entry because Done was not hittable. Screenshot inspection also exposed the amount-label wrapping in finding 14.
- The two pending-insert deletion probes failed as expected from the defect in finding 5. Their temporary source was removed from the app's compiled test target and preserved at `/private/tmp/ReleaseAuditProbeTests.swift`. No full test suite was run.
- `git diff --check` passed.

Session evidence: `/private/tmp/syl-release-audit-build.log`, `/private/tmp/syl-release-audit-tests.xcresult` (iPad), `/private/tmp/syl-release-audit-iphone-tests.xcresult`, and `/private/tmp/syl-release-audit-accessibility-tests.xcresult`. Exported screenshots and UI hierarchy are under `/private/tmp/syl-release-audit-accessibility-attachments`; `70AA631C-6B38-4F7E-8754-807C7DD60CCE.txt` contains the overlapping keyboard/Done geometry. These are local audit artifacts, not bundled application resources.
