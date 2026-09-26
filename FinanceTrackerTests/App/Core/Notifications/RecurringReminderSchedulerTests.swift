import Foundation
import Testing
import UserNotifications
@testable import SageKit

@Suite("Recurring reminder scheduler")
@MainActor
struct RecurringReminderSchedulerTests {
    private enum Failure: Error { case fetch }

    @MainActor
    private final class Clock {
        var date = ISO8601DateFormatter().date(from: "2090-08-10T08:00:00Z")!
    }

    private func summary(_ day: Int = 10, fireDate: Date? = nil, body: String = "Private summary") -> RecurringReminderPlan.Summary {
        RecurringReminderPlan.Summary(
            identifier: "sage.recurring.v1.2090-08-\(String(format: "%02d", day))",
            fireDate: fireDate ?? ISO8601DateFormatter().date(from: "2090-08-\(String(format: "%02d", day))T09:00:00Z")!,
            title: "Upcoming Recurring Expenses", body: body
        )
    }

    private func request(_ identifier: String, body: String = "Sensitive expense $500", category: String = "") -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Old reminder"
        content.body = body
        content.categoryIdentifier = category
        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }

    private func withDefaults(_ test: (UserDefaults) async throws -> Void) async rethrows {
        let suite = "RecurringReminderSchedulerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await test(defaults)
    }

    @Test
    func stableRefreshDoesNotReAddAndUsesAbsolutePrivateTrigger() async throws {
        try await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let planned = summary()
            #expect(scheduler.authorizationStatus == .notDetermined)
            scheduler.refresh(enabled: true, hideDetails: true) { [planned] }
            #expect(scheduler.isRefreshing)
            await scheduler.waitUntilIdle()
            let request = try #require(client.pending.first)
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            #expect(trigger.repeats == false)
            #expect(trigger.dateComponents.calendar?.identifier == .gregorian)
            #expect(trigger.dateComponents.timeZone != nil)
            #expect(trigger.nextTriggerDate() == planned.fireDate)
            #expect(request.content.sound != nil)
            #expect(request.content.userInfo.count == 1)
            #expect(request.content.userInfo["reminderIdentifier"] as? String == planned.identifier)
            scheduler.refresh(enabled: true, hideDetails: true) { [planned] }
            await scheduler.waitUntilIdle()
            #expect(client.added.count == 1)
            #expect(scheduler.scheduledCount == 1)
            #expect(scheduler.authorizationStatus == .authorized)
            #expect(scheduler.errorMessage == nil)
            #expect(!scheduler.isRefreshing)
        }
    }

    @Test(arguments: [0, 10, 64, 70])
    func capacityKeepsEarliestAndPreservesUnrelated(unrelated: Int) async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            client.pending = (0..<unrelated).map { request("other.\($0)") }
            client.pending += [request("recurring-day-old"), request("recurring-added-old")]
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let summaries = (0..<90).map { index in
                summary(index, fireDate: clock.date.addingTimeInterval(Double(index + 1) * 86_400))
            }
            scheduler.refresh(enabled: true, hideDetails: false) { summaries.reversed() }
            await scheduler.waitUntilIdle()
            let capacity = min(60, max(0, 64 - unrelated))
            #expect(client.added.map(\.identifier) == summaries.prefix(capacity).map(\.identifier))
            #expect(scheduler.scheduledCount == capacity)
            #expect(client.pending.filter { !RecurringReminderPlan.owns($0.identifier) }.count == unrelated)
            #expect(client.removed.allSatisfy(RecurringReminderPlan.owns))
            #expect(client.removed.contains("recurring-day-old"))
            #expect(client.removed.contains("recurring-added-old"))
        }
    }

    @Test(arguments: [false, true])
    func fetchFailureScrubsOnlyWhenPrivate(hidden: Bool) async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            let owned = summary().identifier
            client.pending = [request(owned), request("recurring-added-old"), request("other")]
            client.delivered = [owned, "recurring-day-old", "other"].map { request($0) }
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            scheduler.refresh(enabled: true, hideDetails: hidden) {
                if hidden {
                    #expect(client.pending.map(\.identifier) == ["other"])
                    #expect(client.delivered.map(\.identifier) == ["other"])
                }
                throw Failure.fetch
            }
            await scheduler.waitUntilIdle()
            #expect(scheduler.errorMessage != nil)
            #expect(scheduler.scheduledCount == (hidden ? 0 : 2))
            #expect(client.pending.contains { $0.identifier == "other" })
            #expect(client.delivered.contains { $0.identifier == "other" })
            #expect(client.added.isEmpty)
            #expect(client.statusCalls == 1)
        }
    }

    @Test(arguments: [UNAuthorizationStatus.denied, .notDetermined, .authorized])
    func disabledOrUnauthorizedCancelsWithoutFetching(status: UNAuthorizationStatus) async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            client.status = status
            let unrelated = ["other", DailyExpenseReminderScheduler.identifier]
            client.pending = [summary().identifier, "recurring-day-old"].map { request($0) } + unrelated.map { request($0) }
            client.delivered = [request(summary().identifier),
                                request(summary(11).identifier, category: "sage.recurring.v1.private"),
                                request("recurring-added-old")] + unrelated.map { request($0) }
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            scheduler.refresh(enabled: status != .authorized, hideDetails: true) {
                Issue.record("Cancellation must not fetch the plan")
                throw Failure.fetch
            }
            await scheduler.waitUntilIdle()
            #expect(client.pending.map(\.identifier) == unrelated)
            #expect(client.delivered.map(\.identifier) == unrelated)
            #expect(client.removed.allSatisfy(RecurringReminderPlan.owns))
            #expect(client.removedDelivered.allSatisfy(RecurringReminderPlan.owns))
            #expect(scheduler.authorizationStatus == status)
            #expect(scheduler.scheduledCount == 0)
            #expect(scheduler.errorMessage == nil)
        }
    }

    @Test
    func addFailureDoesNotRecordHistoryOrRetryUntilRefresh() async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            client.failAdd = true
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let planned = summary()
            scheduler.refresh(enabled: true, hideDetails: false) { [planned, summary(11)] }
            await scheduler.waitUntilIdle()
            #expect(client.added.count == 1)
            #expect(scheduler.errorMessage != nil)
            #expect(scheduler.scheduledCount == 0)
            #expect(defaults.dictionary(forKey: RecurringReminderScheduler.historyKey)?.isEmpty == true)
            client.failAdd = false
            scheduler.refresh(enabled: true, hideDetails: false) { [planned] }
            await scheduler.waitUntilIdle()
            #expect(client.added.count == 2)
            #expect(scheduler.errorMessage == nil)
            #expect(scheduler.scheduledCount == 1)
        }
    }

    @Test
    func disableWhileAddIsSuspendedCancelsItsResult() async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            client.pending = [request("other")]
            client.delivered = [summary().identifier, "other"].map { request($0) }
            client.blockAdd = true
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let planned = summary()
            scheduler.refresh(enabled: true, hideDetails: false) { [planned, summary(11)] }
            await client.waitForAdd()
            scheduler.refresh(enabled: false, hideDetails: true) {
                Issue.record("Disabled plan must not execute")
                return []
            }
            client.resumeAdd()
            await scheduler.waitUntilIdle()
            #expect(client.added.count == 1)
            #expect(client.pending.map(\.identifier) == ["other"])
            #expect(client.delivered.map(\.identifier) == ["other"])
            #expect(client.removed.contains(planned.identifier))
            #expect(client.maximumActiveAdds == 1)
            #expect(scheduler.scheduledCount == 0)
            #expect(defaults.dictionary(forKey: RecurringReminderScheduler.historyKey)?.isEmpty == true)
        }
    }

    @Test
    func coalescesInFlightChangesAndReplacesStaleSameID() async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            client.blockAdd = true
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let original = summary(body: "Sensitive expense")
            let latest = summary(body: "Private summary")
            scheduler.refresh(enabled: true, hideDetails: false) { [original] }
            await client.waitForAdd()
            scheduler.refresh(enabled: true, hideDetails: false) {
                Issue.record("Intermediate revision must be coalesced")
                return []
            }
            scheduler.refresh(enabled: true, hideDetails: true) { [latest] }
            client.resumeAdd()
            await scheduler.waitUntilIdle()
            #expect(client.added.map(\.content.body) == [original.body, latest.body])
            #expect(client.pending.map(\.content.body) == [latest.body])
            #expect(client.removed == [original.identifier])
            #expect(client.maximumActiveAdds == 1)
            #expect(scheduler.scheduledCount == 1)
        }
    }

    @Test
    func obsoleteAuthorizationResultNeverRunsOldPlan() async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            client.blockStatus = true
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            scheduler.refresh(enabled: true, hideDetails: false) {
                Issue.record("Obsolete plan must not execute")
                return [summary()]
            }
            await client.waitForStatus()
            client.status = .denied
            client.pending = [request(summary().identifier)]
            scheduler.refresh(enabled: true, hideDetails: true) {
                Issue.record("Denied plan must not execute")
                return []
            }
            client.resumeStatus()
            await scheduler.waitUntilIdle()
            #expect(client.statusCalls == 2)
            #expect(scheduler.authorizationStatus == .denied)
            #expect(client.pending.isEmpty)
            #expect(client.added.isEmpty)
        }
    }

    @Test
    func skipsElapsedDatesIncludingWhileAwaitingAdd() async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            client.blockAdd = true
            let first = summary(fireDate: clock.date.addingTimeInterval(60))
            let second = summary(11, fireDate: clock.date.addingTimeInterval(120))
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            scheduler.refresh(enabled: true, hideDetails: false) {
                [summary(8, fireDate: clock.date.addingTimeInterval(-1)), summary(9, fireDate: clock.date), first, second]
            }
            await client.waitForAdd()
            clock.date = second.fireDate
            client.resumeAdd()
            await scheduler.waitUntilIdle()
            #expect(client.added.map(\.identifier) == [first.identifier])
            #expect(client.pending.isEmpty)
            #expect(scheduler.scheduledCount == 0)
            let history = defaults.dictionary(forKey: RecurringReminderScheduler.historyKey) as? [String: Date]
            #expect(history == [first.identifier: first.fireDate])
        }
    }

    @Test
    func elapsedCutoffSuppressesSameNominalDayAcrossRestartAndTravel() async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            let planned = summary()
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            scheduler.refresh(enabled: true, hideDetails: false) { [planned] }
            await scheduler.waitUntilIdle()
            clock.date = planned.fireDate
            client.pending = []
            let restarted = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let westward = summary(fireDate: planned.fireDate.addingTimeInterval(8 * 3_600), body: "Changed lead and details")
            restarted.refresh(enabled: true, hideDetails: false) { [westward, summary(11)] }
            await restarted.waitUntilIdle()
            #expect(client.added.map(\.identifier) == [planned.identifier, summary(11).identifier])
            #expect(client.pending.map(\.identifier) == [summary(11).identifier])
            #expect(restarted.scheduledCount == 1)
        }
    }

    @Test(arguments: [false, true])
    func changingNineAMToEveningRespectsOriginalCutoff(afterCutoff: Bool) async throws {
        try await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let original = summary()
            scheduler.refresh(enabled: true, hideDetails: true) { [original] }
            await scheduler.waitUntilIdle()
            #expect(client.pending.map(\.identifier) == [original.identifier])

            clock.date = ISO8601DateFormatter().date(from: afterCutoff
                ? "2090-08-10T10:00:00Z" : "2090-08-10T08:59:00Z")!
            if afterCutoff {
                // Delivery may already have been dismissed; history must be sufficient.
                client.pending = []
            }
            let evening = summary(fireDate: ISO8601DateFormatter().date(from: "2090-08-10T18:45:00Z")!)
            scheduler.refresh(enabled: true, hideDetails: true) { [evening] }
            await scheduler.waitUntilIdle()

            #expect(client.added.count == (afterCutoff ? 1 : 2))
            #expect(scheduler.scheduledCount == (afterCutoff ? 0 : 1))
            #expect(scheduler.errorMessage == nil)
            #expect(defaults.dictionary(forKey: RecurringReminderScheduler.historyKey) as? [String: Date]
                == [original.identifier: afterCutoff ? original.fireDate : evening.fireDate])
            if afterCutoff {
                #expect(client.pending.isEmpty)
            } else {
                #expect(client.pending.map(\.identifier) == [original.identifier])
                let pending = try #require(client.pending.first)
                let trigger = try #require(pending.trigger as? UNCalendarNotificationTrigger)
                #expect(trigger.nextTriggerDate() == evening.fireDate)

                // Passing the obsolete 9 AM cutoff must not suppress its valid replacement.
                clock.date = ISO8601DateFormatter().date(from: "2090-08-10T10:00:00Z")!
                scheduler.refresh(enabled: true, hideDetails: true) { [evening] }
                await scheduler.waitUntilIdle()
                #expect(client.added.count == 2)
                #expect(client.pending.map(\.identifier) == [evening.identifier])
                #expect(scheduler.scheduledCount == 1)
            }
        }
    }

    @Test
    func futureCutoffsAllowReplacementAndClearedRequestsToBeRestored() async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let original = summary()
            scheduler.refresh(enabled: true, hideDetails: false) { [original] }
            await scheduler.waitUntilIdle()
            client.pending = []
            scheduler.refresh(enabled: true, hideDetails: false) { [original] }
            await scheduler.waitUntilIdle()
            #expect(client.added.count == 2)
            let shifted = summary(fireDate: original.fireDate.addingTimeInterval(3_600))
            scheduler.refresh(enabled: true, hideDetails: false) { [shifted] }
            await scheduler.waitUntilIdle()
            #expect(client.added.count == 3)
            #expect(defaults.dictionary(forKey: RecurringReminderScheduler.historyKey) as? [String: Date]
                == [shifted.identifier: shifted.fireDate])
            scheduler.refresh(enabled: true, hideDetails: false) { [] }
            await scheduler.waitUntilIdle()
            #expect(client.pending.isEmpty)
            #expect(defaults.dictionary(forKey: RecurringReminderScheduler.historyKey)?.isEmpty == true)
        }
    }

    @Test
    func cancellationPreservesElapsedHistoryAndPrunesAfterOneHundredDays() async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let today = summary()
            let tomorrow = summary(11)
            scheduler.refresh(enabled: true, hideDetails: false) { [today, tomorrow] }
            await scheduler.waitUntilIdle()
            clock.date = today.fireDate
            client.pending.removeAll { $0.identifier == today.identifier }
            scheduler.refresh(enabled: false, hideDetails: false) { [] }
            await scheduler.waitUntilIdle()
            #expect(defaults.dictionary(forKey: RecurringReminderScheduler.historyKey) as? [String: Date]
                == [today.identifier: today.fireDate])
            clock.date = today.fireDate.addingTimeInterval(100 * 86_400)
            scheduler.refresh(enabled: false, hideDetails: false) { [] }
            await scheduler.waitUntilIdle()
            #expect(defaults.dictionary(forKey: RecurringReminderScheduler.historyKey)?.isEmpty == true)
        }
    }

    @Test(arguments: [false, true])
    func replacementCrossingPreviousCutoffCannotRenewCompletedDay(addFails: Bool) async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let original = summary()
            scheduler.refresh(enabled: true, hideDetails: false) { [original] }
            await scheduler.waitUntilIdle()
            client.blockAdd = true
            client.failAdd = addFails
            let shifted = summary(fireDate: original.fireDate.addingTimeInterval(8 * 3_600))
            scheduler.refresh(enabled: true, hideDetails: false) { [shifted] }
            await client.waitForAdd()
            clock.date = original.fireDate
            client.resumeAdd()
            await scheduler.waitUntilIdle()
            #expect(client.pending.isEmpty)
            #expect(scheduler.scheduledCount == 0)
            #expect((scheduler.errorMessage != nil) == addFails)
            #expect(defaults.dictionary(forKey: RecurringReminderScheduler.historyKey) as? [String: Date]
                == [original.identifier: original.fireDate])
            scheduler.refresh(enabled: true, hideDetails: false) { [shifted] }
            await scheduler.waitUntilIdle()
            #expect(client.added.count == 2)
        }
    }

    @Test
    func failedReplacementRemovesStaleDetailsAndFutureCutoffUntilExplicitRetry() async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            client.pending = [request("other")]
            let original = summary(body: "Expense total $500")
            scheduler.refresh(enabled: true, hideDetails: false) { [original] }
            await scheduler.waitUntilIdle()
            client.failAdd = true
            let edited = summary(body: "Expense total $100")
            scheduler.refresh(enabled: true, hideDetails: false) { [edited] }
            await scheduler.waitUntilIdle()
            #expect(client.pending.map(\.identifier) == ["other"])
            #expect(client.removed == [original.identifier])
            #expect(client.added.count == 2)
            #expect(scheduler.scheduledCount == 0)
            #expect(scheduler.errorMessage != nil)
            #expect(defaults.dictionary(forKey: RecurringReminderScheduler.historyKey)?.isEmpty == true)
            client.failAdd = false
            scheduler.refresh(enabled: true, hideDetails: false) { [edited] }
            await scheduler.waitUntilIdle()
            #expect(client.added.count == 3)
            #expect(client.pending.filter { RecurringReminderPlan.owns($0.identifier) }.map(\.content.body) == [edited.body])
            #expect(scheduler.scheduledCount == 1)
            #expect(scheduler.errorMessage == nil)
            #expect(defaults.dictionary(forKey: RecurringReminderScheduler.historyKey) as? [String: Date]
                == [edited.identifier: edited.fireDate])
        }
    }

    @Test(arguments: [false, true])
    func repeatedPrivacyRefreshPreservesPrivateDeliveredReminders(fetchFails: Bool) async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let privateID = summary().identifier
            let unrelated = ["other", DailyExpenseReminderScheduler.identifier]
            client.delivered = [request(privateID, category: "sage.recurring.v1.private")]
                + [summary(11).identifier, "recurring-day-old", "recurring-added-old"].map { request($0) }
                + unrelated.map { request($0) }
            for _ in 0..<2 {
                scheduler.refresh(enabled: true, hideDetails: true) {
                    #expect(client.delivered.map(\.identifier) == [privateID] + unrelated)
                    if fetchFails { throw Failure.fetch }
                    return []
                }
                await scheduler.waitUntilIdle()
                #expect(client.delivered.map(\.identifier) == [privateID] + unrelated)
                #expect((scheduler.errorMessage != nil) == fetchFails)
            }
            #expect(client.deliveredCalls == 2)
            #expect(client.removedDelivered == [summary(11).identifier, "recurring-day-old", "recurring-added-old"])
        }
    }

    @Test
    func privacyScrubsPreviouslyScheduledDetailsEvenWhenFetchFails() async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            let original = summary(body: "Sensitive expense $500")
            scheduler.refresh(enabled: true, hideDetails: false) { [original] }
            await scheduler.waitUntilIdle()
            client.delivered = [original.identifier, "other"].map { request($0) }
            scheduler.refresh(enabled: true, hideDetails: true) {
                #expect(client.pending.isEmpty)
                #expect(client.delivered.map(\.identifier) == ["other"])
                throw Failure.fetch
            }
            await scheduler.waitUntilIdle()
            #expect(scheduler.errorMessage != nil)
            #expect(scheduler.scheduledCount == 0)
            #expect(defaults.dictionary(forKey: RecurringReminderScheduler.historyKey)?.isEmpty == true)
        }
    }

    @Test(arguments: [UNAuthorizationStatus.provisional, .ephemeral])
    func nonPromptingAuthorizedStatusesCanSchedule(status: UNAuthorizationStatus) async {
        await withDefaults { defaults in
            let client = TestNotificationClient()
            let clock = Clock()
            client.status = status
            let scheduler = RecurringReminderScheduler(defaults: defaults, client: client, now: { clock.date })
            scheduler.refresh(enabled: true, hideDetails: true) { [summary()] }
            await scheduler.waitUntilIdle()
            #expect(scheduler.authorizationStatus == status)
            #expect(scheduler.scheduledCount == 1)
        }
    }
}
