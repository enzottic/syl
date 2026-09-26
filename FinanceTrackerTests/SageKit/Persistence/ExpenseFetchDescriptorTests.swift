import Foundation
import SwiftData
import Testing
@testable import SageKit

@Suite("Category detail and Home month queries")
@MainActor
struct ExpenseFetchDescriptorTests {
    @Test(arguments: [3, 11])
    func recurringQueryUsesScheduledMonthRatherThanEditedDate(month: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let selected = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: 15)))
        let interval = try #require(calendar.dateInterval(of: .month, for: selected))
        let container = try SageModelContainer.make(for: .test)
        let context = ModelContext(container)
        let ruleID = UUID()
        for (name, scheduled, recorded) in [
            ("Before month", interval.start.addingTimeInterval(-1), selected),
            ("Moved start", interval.start, interval.end),
            ("Moved end", interval.end.addingTimeInterval(-0.001), interval.start.addingTimeInterval(-1)),
            ("Next month", interval.end, selected)
        ] {
            context.insert(Expense(name: name, amount: 10, date: recorded, recurringExpenseId: ruleID,
                                   recurringOccurrenceKey: RecurringExpenseOccurrence.key(ruleID: ruleID, scheduledDate: scheduled)))
        }
        context.insert(Expense(name: "Manual", amount: 10, date: selected))
        let missing = Expense(name: "Not backfilled", amount: 10, date: selected, recurringExpenseId: ruleID)
        missing.recurringScheduledDate = nil
        context.insert(missing)
        try context.save()

        let reader = ModelContext(container)
        let matches = try reader.fetch(ExpenseFetchDescriptors.recurringScheduled(in: selected, calendar: calendar))
        #expect(Set(matches.map(\.name)) == ["Moved start", "Moved end"])
        let nextMonth = try reader.fetch(ExpenseFetchDescriptors.recurringScheduled(in: interval.end, calendar: calendar))
        #expect(nextMonth.map(\.name) == ["Next month"])
    }

    @Test(arguments: [2, 3, 8, 12])
    func categoryDetailExcludesNextMonth(month: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let selected = try #require(calendar.date(from: DateComponents(year: 2024, month: month, day: 15)))
        let interval = try #require(calendar.dateInterval(of: .month, for: selected))
        let container = try SageModelContainer.make(for: .test)
        let context = ModelContext(container)
        for (name, amount, category, date) in [
            ("Before month", 100.0, ExpenseCategory.needs, interval.start.addingTimeInterval(-1)),
            ("Month start", 10.0, .needs, interval.start),
            ("Other category", 100.0, .wants, selected),
            ("Month end", 20.0, .needs, interval.end.addingTimeInterval(-0.001)),
            ("Next month", 200.0, .needs, interval.end)
        ] {
            context.insert(Expense(name: name, amount: amount, category: category, date: date))
        }
        try context.save()

        let reader = ModelContext(container)
        let expenses = try reader.fetch(ExpenseFetchDescriptors.month(selected, calendar: calendar))
            .filter { $0.category == .needs }
        #expect(expenses.map(\.name) == ["Month end", "Month start"])
        #expect(expenses.total == 30)
        let nextMonth = try reader.fetch(ExpenseFetchDescriptors.month(interval.end, calendar: calendar))
        #expect(nextMonth.map(\.name) == ["Next month"])
    }

    @Test
    func homeComparisonKeepsMonthBoundarySeparateFromInclusiveCutoff() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let previousStart = try #require(calendar.date(byAdding: .month, value: -1, to: start))
        let end = try #require(calendar.date(byAdding: .month, value: 1, to: start))
        let cutoff = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 15, hour: 12)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)))
        let container = try SageModelContainer.make(for: .test)
        let context = ModelContext(container)
        for (name, amount, date) in [
            ("Before range", 999.0, previousStart.addingTimeInterval(-1)),
            ("Previous start", 10.0, previousStart),
            ("At cutoff", 20.0, cutoff),
            ("After cutoff", 5.0, cutoff.addingTimeInterval(1)),
            ("Previous end", 7.0, start.addingTimeInterval(-0.001)),
            ("Selected midnight", 40.0, start),
            ("Exactly now", 2.0, now),
            ("Later", 3.0, now.addingTimeInterval(1)),
            ("Next month", 999.0, end)
        ] {
            context.insert(Expense(name: name, amount: amount, date: date))
        }
        try context.save()
        let reader = ModelContext(container)
        let monthly = try reader.fetch(ExpenseFetchDescriptors.month(start, calendar: calendar))
        #expect(monthly.map(\.name) == ["Later", "Exactly now", "Selected midnight"])
        #expect(monthly.total == 45)
        let history = try reader.fetch(ExpenseFetchDescriptors.range(start: previousStart, end: end))
        #expect(history.count == 7)

        let current = SpendingMonthSummary(month: start, expenses: history, now: now, calendar: calendar)
        #expect(current.previousTotal == 30)
        #expect(current.total == 42)
        let completed = SpendingMonthSummary(month: start, expenses: history, now: end, calendar: calendar)
        #expect(completed.previousTotal == 42)
        #expect(completed.total == 45)
    }
}
