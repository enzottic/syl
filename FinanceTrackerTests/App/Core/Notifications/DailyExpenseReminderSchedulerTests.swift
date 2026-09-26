import Foundation
import Testing
import UserNotifications
@testable import SageKit

@Suite("Daily expense reminder scheduler")
@MainActor
struct DailyExpenseReminderSchedulerTests {
    private let unrelated = ["other", "sage.recurring.v1.2090-08-10", "recurring-day-old", "recurring-added-old"]

    private func request(_ identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(identifier: identifier, content: UNMutableNotificationContent(), trigger: nil)
    }

    @Test(arguments: [UNAuthorizationStatus.authorized, .provisional, .ephemeral])
    func stableRefreshUsesRepeatingFloatingLocalTrigger(status: UNAuthorizationStatus) async throws {
        let client = TestNotificationClient()
        client.status = status
        client.pending = unrelated.map { request($0) }
        client.delivered = (unrelated + [DailyExpenseReminderScheduler.identifier]).map { request($0) }
        let scheduler = DailyExpenseReminderScheduler(client: client)
        #expect(scheduler.authorizationStatus == .notDetermined)
        scheduler.refresh(enabled: true)
        #expect(scheduler.isRefreshing)
        await scheduler.waitUntilIdle()

        let scheduled = try #require(client.added.first)
        let trigger = try #require(scheduled.trigger as? UNCalendarNotificationTrigger)
        #expect(scheduled.identifier == "sage.daily-expense-entry.v1")
        #expect(scheduled.content.title == "Daily Expense Reminder")
        #expect(scheduled.content.body == "Add expenses from the day.")
        #expect(scheduled.content.sound != nil)
        #expect(trigger.repeats)
        #expect(trigger.dateComponents == DateComponents(hour: 20, minute: 0))
        #expect(trigger.dateComponents.calendar == nil)
        #expect(trigger.dateComponents.timeZone == nil)
        #expect(trigger.dateComponents.year == nil)
        #expect(trigger.dateComponents.month == nil)
        #expect(trigger.dateComponents.day == nil)
        #expect(trigger.dateComponents.second == nil)

        scheduler.refresh(enabled: true)
        await scheduler.waitUntilIdle()
        // Diff against the center, not an in-memory record, including after restart.
        let restarted = DailyExpenseReminderScheduler(client: client)
        restarted.refresh(enabled: true)
        await restarted.waitUntilIdle()
        #expect(client.added.count == 1)
        #expect(client.pending.map(\.identifier) == unrelated + [scheduled.identifier])
        #expect(client.delivered.map(\.identifier) == unrelated + [scheduled.identifier])
        #expect(client.removed.isEmpty)
        #expect(client.removedDelivered.isEmpty)
        #expect(scheduler.authorizationStatus == status)
        #expect(scheduler.errorMessage == nil)
        #expect(!scheduler.isRefreshing)
    }

    @Test(arguments: [0, 1439, -1, 1440, Int.min, Int.max])
    func customTimesAndInvalidFallback(minutes: Int) async throws {
        let client = TestNotificationClient()
        let scheduler = DailyExpenseReminderScheduler(client: client)
        scheduler.refresh(enabled: true, timeMinutes: minutes)
        await scheduler.waitUntilIdle()
        let scheduled = try #require(client.pending.first)
        let trigger = try #require(scheduled.trigger as? UNCalendarNotificationTrigger)
        let expected = (0..<1440).contains(minutes) ? minutes : 1200
        #expect(trigger.repeats)
        #expect(trigger.dateComponents == DateComponents(hour: expected / 60, minute: expected % 60))
    }

    @Test(arguments: [UNAuthorizationStatus.denied, .notDetermined, .authorized])
    func disabledOrUnauthorizedRemovesOnlyOwnedNotifications(status: UNAuthorizationStatus) async {
        let client = TestNotificationClient()
        client.status = status
        let identifier = DailyExpenseReminderScheduler.identifier
        client.pending = (unrelated + [identifier]).map { request($0) }
        client.delivered = (unrelated + [identifier]).map { request($0) }
        let scheduler = DailyExpenseReminderScheduler(client: client)
        scheduler.refresh(enabled: status != .authorized)
        await scheduler.waitUntilIdle()
        #expect(client.pending.map(\.identifier) == unrelated)
        #expect(client.delivered.map(\.identifier) == unrelated)
        #expect(client.removed == [identifier])
        #expect(client.removedDelivered == [identifier])
        #expect(client.added.isEmpty)
        #expect(client.statusCalls == 1)
        #expect(scheduler.authorizationStatus == status)
        #expect(scheduler.errorMessage == nil)
        #expect(!scheduler.isRefreshing)
    }

    @Test(arguments: [63, 64, 70])
    func capacityReportsFailureWithoutDisplacingOthers(count: Int) async {
        let client = TestNotificationClient()
        let identifiers = (0..<count).map { "other.\($0)" }
        client.pending = (identifiers + [DailyExpenseReminderScheduler.identifier]).map { request($0) }
        let scheduler = DailyExpenseReminderScheduler(client: client)
        scheduler.refresh(enabled: true)
        await scheduler.waitUntilIdle()
        #expect(client.pending.filter { $0.identifier != DailyExpenseReminderScheduler.identifier }.map(\.identifier) == identifiers)
        #expect(client.added.count == (count < 64 ? 1 : 0))
        #expect(client.pending.count == (count < 64 ? 64 : count))
        #expect((scheduler.errorMessage != nil) == (count >= 64))
        #expect(client.removed.allSatisfy { $0 == DailyExpenseReminderScheduler.identifier })
        if count >= 64 {
            client.pending.removeLast(count - 63)
            scheduler.refresh(enabled: true)
            await scheduler.waitUntilIdle()
            #expect(client.pending.count == 64)
            #expect(scheduler.errorMessage == nil)
        }
    }

    @Test(arguments: [false, true])
    func blockedAddCoalescesChangesAndCancelsObsoleteResult(disable: Bool) async throws {
        let client = TestNotificationClient()
        client.pending = unrelated.map { request($0) }
        client.delivered = (unrelated + [DailyExpenseReminderScheduler.identifier]).map { request($0) }
        client.blockAdd = true
        let scheduler = DailyExpenseReminderScheduler(client: client)
        scheduler.refresh(enabled: true)
        await client.waitForAdd()
        scheduler.refresh(enabled: true, timeMinutes: 600)
        scheduler.refresh(enabled: !disable, timeMinutes: 1439)
        client.resumeAdd()
        await scheduler.waitUntilIdle()
        #expect(client.maximumActiveAdds == 1)
        #expect(client.added.count == (disable ? 1 : 2))
        #expect(client.removed.contains(DailyExpenseReminderScheduler.identifier))
        #expect(client.removed.allSatisfy { $0 == DailyExpenseReminderScheduler.identifier })
        #expect(client.pending.filter { $0.identifier != DailyExpenseReminderScheduler.identifier }.map(\.identifier) == unrelated)
        if disable {
            #expect(client.pending.map(\.identifier) == unrelated)
            #expect(client.delivered.map(\.identifier) == unrelated)
        } else {
            let scheduled = try #require(client.pending.last)
            let trigger = try #require(scheduled.trigger as? UNCalendarNotificationTrigger)
            #expect(trigger.dateComponents == DateComponents(hour: 23, minute: 59))
            #expect(client.delivered.map(\.identifier) == unrelated + [DailyExpenseReminderScheduler.identifier])
        }
        #expect(scheduler.errorMessage == nil)
        #expect(!scheduler.isRefreshing)
    }

    @Test
    func redundantRefreshDuringAddDoesNotReAdd() async {
        let client = TestNotificationClient()
        client.blockAdd = true
        let scheduler = DailyExpenseReminderScheduler(client: client)
        scheduler.refresh(enabled: true)
        await client.waitForAdd()
        scheduler.refresh(enabled: true, timeMinutes: -1)
        client.resumeAdd()
        await scheduler.waitUntilIdle()
        #expect(client.added.count == 1)
        #expect(client.pending.count == 1)
        #expect(client.removed.isEmpty)
    }

    @Test
    func obsoleteAuthorizationResultIsIgnored() async {
        let client = TestNotificationClient()
        client.blockStatus = true
        client.pending = [request(DailyExpenseReminderScheduler.identifier)]
        let scheduler = DailyExpenseReminderScheduler(client: client)
        scheduler.refresh(enabled: true)
        await client.waitForStatus()
        client.status = .denied
        scheduler.refresh(enabled: true)
        client.resumeStatus()
        await scheduler.waitUntilIdle()
        #expect(client.statusCalls == 2)
        #expect(scheduler.authorizationStatus == .denied)
        #expect(client.added.isEmpty)
        #expect(client.pending.isEmpty)
    }

    @Test
    func failedReplacementRemovesOldTimeAndRetriesOnlyOnRefresh() async throws {
        let client = TestNotificationClient()
        client.pending = unrelated.map { request($0) }
        client.delivered = (unrelated + [DailyExpenseReminderScheduler.identifier]).map { request($0) }
        let scheduler = DailyExpenseReminderScheduler(client: client)
        scheduler.refresh(enabled: true)
        await scheduler.waitUntilIdle()
        client.failAdd = true
        scheduler.refresh(enabled: true, timeMinutes: 0)
        await scheduler.waitUntilIdle()
        #expect(client.pending.map(\.identifier) == unrelated)
        #expect(client.delivered.map(\.identifier) == unrelated + [DailyExpenseReminderScheduler.identifier])
        #expect(client.removed == [DailyExpenseReminderScheduler.identifier])
        #expect(client.added.count == 2)
        #expect(scheduler.errorMessage != nil)
        #expect(!scheduler.isRefreshing)

        client.failAdd = false
        scheduler.refresh(enabled: true, timeMinutes: 0)
        await scheduler.waitUntilIdle()
        let scheduled = try #require(client.pending.last)
        let trigger = try #require(scheduled.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents == DateComponents(hour: 0, minute: 0))
        #expect(client.added.count == 3)
        #expect(scheduler.errorMessage == nil)
    }

    @Test
    func obsoleteAddFailureDoesNotLeakIntoLatestRefresh() async throws {
        let client = TestNotificationClient()
        client.blockAdd = true
        client.failAdd = true
        let scheduler = DailyExpenseReminderScheduler(client: client)
        scheduler.refresh(enabled: true)
        await client.waitForAdd()
        client.failAdd = false
        scheduler.refresh(enabled: true, timeMinutes: 0)
        client.resumeAdd()
        await scheduler.waitUntilIdle()
        let scheduled = try #require(client.pending.first)
        let trigger = try #require(scheduled.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents == DateComponents(hour: 0, minute: 0))
        #expect(client.added.count == 2)
        #expect(client.maximumActiveAdds == 1)
        #expect(scheduler.errorMessage == nil)
    }
}
