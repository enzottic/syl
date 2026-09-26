import Foundation
import SwiftData
import Testing
@testable import SageKit

@Suite("Spending calendar month")
struct SpendingCalendarMonthTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        return calendar
    }

    @Test(arguments: [(2026, 8, 31, 6), (2026, 2, 28, 0), (2024, 2, 29, 4), (2026, 4, 30, 3)])
    func laysOutSundayFirstMonths(year: Int, month: Int, count: Int, padding: Int) throws {
        let date = try #require(calendar.date(from: DateComponents(year: year, month: month, day: 15)))
        let result = SpendingCalendarMonth(month: date, expenses: [], calendar: calendar)
        #expect(result.leadingEmptyDays == padding)
        #expect(result.days.count == count)
        #expect(result.days.allSatisfy { $0.amount == 0 })
        #expect(result.days.map { calendar.component(.day, from: $0.date) } == Array(1...count))
    }

    @Test @MainActor
    func sumsRecordedExpensesAndRefundsWithExclusiveMonthEnd() throws {
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let end = try #require(calendar.date(byAdding: .month, value: 1, to: start))
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        let expenses = [
            Expense(name: "Before month", amount: 999, date: start.addingTimeInterval(-1)),
            Expense(name: "Needs", amount: 20.25, category: .needs, date: start),
            Expense(name: "Wants", amount: 15.50, category: .wants, date: start.addingTimeInterval(3600)),
            Expense(name: "Savings", amount: 10, category: .savings, date: start.addingTimeInterval(7200)),
            Expense(name: "Refund", amount: -5.25, date: start.addingTimeInterval(10800)),
            Expense(name: "Refund only", amount: -12.50, date: nextDay),
            Expense(name: "Last second", amount: 8, date: end.addingTimeInterval(-1)),
            Expense(name: "Next month", amount: 999, date: end)
        ]
        let result = SpendingCalendarMonth(month: start, expenses: expenses, calendar: calendar)
        #expect(result.days[0].amount == 40.50)
        #expect(result.days[1].amount == -12.50)
        #expect(result.days[2].amount == 0)
        #expect(result.days[30].amount == 8)
        #expect(result.days.reduce(0) { $0 + $1.amount } == 36)
    }

    @Test(arguments: [(3, 8, 23), (11, 1, 25)]) @MainActor
    func groupsLocalDaysAcrossDaylightSaving(month: Int, day: Int, hours: Int) throws {
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        #expect(nextDay.timeIntervalSince(start) == Double(hours * 3600))
        let expenses = [
            Expense(name: "Start", amount: 10, date: start),
            Expense(name: "End", amount: 20, date: nextDay.addingTimeInterval(-1)),
            Expense(name: "Next day", amount: 50, date: nextDay)
        ]
        let result = SpendingCalendarMonth(month: start, expenses: expenses, calendar: calendar)
        #expect(result.days[day - 1].amount == 30)
        #expect(result.days[day].amount == 50)
        #expect(result.days.allSatisfy { calendar.startOfDay(for: $0.date) == $0.date })
    }
}

extension SpendingCalendarMonthTests {
    @Test @MainActor
    func projectsEveryFutureOccurrenceThroughInclusiveEndDate() throws {
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let end = try #require(calendar.date(byAdding: .day, value: 3, to: today))
        let rule = RecurringExpenseRule(name: "Coffee", amount: 5, note: "", category: .wants,
                                        frequency: .daily, startDate: today, endDate: end,
                                        recurrenceTimeZoneIdentifier: calendar.timeZone.identifier)
        let month = SpendingCalendarMonth(month: today, expenses: [], recurringRules: [rule], now: today, calendar: calendar)
        #expect(month.days[9].amount == 0)
        #expect(month.days[10...12].allSatisfy { $0.amount == 5 && $0.upcomingExpenses.count == 1 })
        #expect(month.days[10...12].allSatisfy { $0.upcomingExpenses.first?.category == .wants })
        #expect(month.days[13].amount == 0)
        #expect(month.days.reduce(0) { $0 + $1.amount } == 15)
    }

    @Test @MainActor
    func combinesRecordedAndProjectedWithoutDuplicatingGeneratedOccurrences() throws {
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let rule = RecurringExpenseRule(name: "Subscription", amount: 15, note: "", category: .wants,
                                        frequency: .daily, startDate: tomorrow,
                                        recurrenceTimeZoneIdentifier: calendar.timeZone.identifier)
        let generated = Expense(name: "Already recorded", amount: 12, date: tomorrow,
                                recurringExpenseId: rule.id,
                                recurringOccurrenceKey: RecurringExpenseOccurrence.key(ruleID: rule.id, scheduledDate: tomorrow))
        let other = Expense(name: "Other", amount: 3, date: tomorrow)
        let legacy = Expense(name: "Legacy recorded", amount: 12, date: tomorrow, recurringExpenseId: rule.id)
        let legacyResult = SpendingCalendarMonth(month: today, expenses: [legacy], recurringRules: [rule], now: today, calendar: calendar)
        #expect(legacyResult.days[10].amount == 12)
        #expect(legacyResult.days[10].upcomingExpenses.isEmpty)
        let result = SpendingCalendarMonth(month: today, expenses: [generated, other], recurringRules: [rule], now: today, calendar: calendar)
        #expect(result.days[10].amount == 15)
        #expect(result.days[10].expenses.count == 2)
        #expect(result.days[10].upcomingExpenses.isEmpty)
        #expect(result.days[11].upcomingAmount == 15)

        // A moved expense still fulfills its original occurrence, even outside this month.
        generated.date = calendar.date(byAdding: .month, value: -1, to: tomorrow)!
        let container = try SageModelContainer.make(for: .test)
        container.mainContext.insert(generated)
        try container.mainContext.save()
        let existing = try ModelContext(container).fetch(ExpenseFetchDescriptors.recurringScheduled(in: today, calendar: calendar))
        let moved = SpendingCalendarMonth(month: today, expenses: [other], recurringRules: [rule], now: today,
                                          existingRecurringExpenses: existing, calendar: calendar)
        #expect(moved.days[10].amount == 3)
        #expect(moved.days[10].upcomingExpenses.isEmpty)

        let additional = RecurringExpenseRule(name: "Second subscription", amount: 8, note: "", category: .needs,
                                              frequency: .monthly, startDate: tomorrow)
        let mixed = SpendingCalendarMonth(month: today, expenses: [other], recurringRules: [additional], now: today, calendar: calendar)
        #expect(mixed.days[10].amount == 11)
        #expect(mixed.days[10].upcomingAmount == 8)
        #expect(mixed.days[10].upcomingExpenses.first?.name == "Second subscription")
        #expect(mixed.days[10].upcomingExpenses.first?.category == .needs)
    }

    @Test @MainActor
    func respectsGenerationCursorAndFixedMonthlyAnchor() throws {
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31)))
        let february = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 28)))
        let march = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let rule = RecurringExpenseRule(name: "Rent", amount: 100, note: "", category: .needs,
                                        frequency: .monthly, startDate: start, lastGeneratedDate: february,
                                        recurrenceTimeZoneIdentifier: calendar.timeZone.identifier)
        let result = SpendingCalendarMonth(month: march, expenses: [], recurringRules: [rule], now: february, calendar: calendar)
        #expect(result.days[30].upcomingAmount == 100)
        #expect(result.days[27].amount == 0)
        #expect(result.days.reduce(0) { $0 + $1.amount } == 100)
        let past = SpendingCalendarMonth(month: start, expenses: [], recurringRules: [rule], now: february, calendar: calendar)
        #expect(past.days.allSatisfy { $0.upcomingExpenses.isEmpty })
    }
}
