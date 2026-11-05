import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Denver")!
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@MainActor
private func makeStore() throws -> ExpenseStore {
    ExpenseStore(modelContainer: try SageModelContainer.make(for: .test))
}

@Suite("Expense search", .serialized)
struct ExpenseSearchTests {
    @Test @MainActor
    func dateRangeIncludesWholeDaysAtBothEnds() throws {
        let store = try makeStore()
        let before = Expense(name: "Before", amount: 1, date: day(2026, 10, 31, hour: 23))
        let firstMorning = Expense(name: "First", amount: 1, date: day(2026, 11, 1, hour: 0))
        let lastNight = Expense(name: "Last", amount: 1, date: day(2026, 11, 3, hour: 23))
        let after = Expense(name: "After", amount: 1, date: day(2026, 11, 4, hour: 0))
        [before, firstMorning, lastNight, after].forEach(store.addExpense)
        try store.save()

        let result = try store.searchExpenses(
            ExpenseSearchCriteria(startDate: day(2026, 11, 1, hour: 15), endDate: day(2026, 11, 3, hour: 1)),
            calendar: calendar
        )

        #expect(Set(result.expenses.map(\.name)) == ["First", "Last"])
    }

    @Test @MainActor
    func reversedDatesAndAmountsAreSwapped() throws {
        let store = try makeStore()
        store.addExpense(Expense(name: "In", amount: 15, date: day(2026, 11, 2)))
        store.addExpense(Expense(name: "Out", amount: 50, date: day(2026, 11, 2)))
        try store.save()

        let result = try store.searchExpenses(
            ExpenseSearchCriteria(startDate: day(2026, 11, 5), endDate: day(2026, 11, 1),
                                  minimumAmount: 20, maximumAmount: 10),
            calendar: calendar
        )

        #expect(result.expenses.map(\.name) == ["In"])
    }

    @Test @MainActor
    func filtersByCategoryTagTextAndAmount() throws {
        let store = try makeStore()
        let dining = ExpenseTag(name: "Dining Out", uiColor: .orange, emoji: "🍽️")
        store.context.insert(dining)
        let match = Expense(name: "Bistro", amount: 42, category: .wants, tags: [dining], note: "Birthday dinner")
        store.addExpense(match)
        store.addExpense(Expense(name: "Bistro", amount: 42, category: .needs, tags: [dining]))     // wrong category
        store.addExpense(Expense(name: "Groceries", amount: 42, category: .wants))                // no tag
        store.addExpense(Expense(name: "Cafe", amount: 8, category: .wants, tags: [dining]))       // too small
        try store.save()

        let result = try store.searchExpenses(ExpenseSearchCriteria(
            text: "birthday", category: .wants, tagNames: ["dining"], minimumAmount: 20
        ))

        #expect(result.expenses.map(\.id) == [match.id])
        #expect(result.matchCount == 1)
    }

    @Test @MainActor
    func textMatchesNameNoteOrTagNameIgnoringCaseAndAccents() throws {
        let store = try makeStore()
        let tag = ExpenseTag(name: "Café", uiColor: .brown, emoji: "☕")
        store.context.insert(tag)
        store.addExpense(Expense(name: "CAFE LUNA", amount: 5))
        store.addExpense(Expense(name: "Beans", amount: 5, note: "from the cafe"))
        store.addExpense(Expense(name: "Latte", amount: 5, tags: [tag]))
        store.addExpense(Expense(name: "Rent", amount: 900))
        try store.save()

        let result = try store.searchExpenses(ExpenseSearchCriteria(text: "  café "))

        #expect(Set(result.expenses.map(\.name)) == ["CAFE LUNA", "Beans", "Latte"])
    }

    @Test @MainActor
    func ordersThenLimitsButCountsAndTotalsEveryMatch() throws {
        let store = try makeStore()
        for (index, amount) in [10.0, 40, 25, 5].enumerated() {
            store.addExpense(Expense(name: "Item \(index)", amount: amount, date: day(2026, 11, 1 + index)))
        }
        try store.save()

        let largest = try store.searchExpenses(ExpenseSearchCriteria(order: .largest, limit: 2))
        let oldest = try store.searchExpenses(ExpenseSearchCriteria(order: .oldest, limit: 1))
        let smallest = try store.searchExpenses(ExpenseSearchCriteria(order: .smallest))

        #expect(largest.expenses.map(\.amount) == [40, 25])
        #expect(largest.matchCount == 4)
        #expect(largest.total == 80)
        #expect(oldest.expenses.map(\.name) == ["Item 0"])
        #expect(smallest.expenses.map(\.amount) == [5, 10, 25, 40])
    }

    @Test
    func limitIsClampedAndDefaulted() {
        #expect(ExpenseSearchCriteria().limit == ExpenseSearchCriteria.defaultLimit)
        #expect(ExpenseSearchCriteria(limit: 0).limit == 1)
        #expect(ExpenseSearchCriteria(limit: 5_000).limit == ExpenseSearchCriteria.maximumLimit)
    }

    @Test
    func dialogDescribesCountTotalAndTruncation() {
        let none = ExpenseSearchResult(expenses: [], matchCount: 0, total: 0)
        let one = ExpenseSearchResult(expenses: [Expense(name: "A", amount: 5)], matchCount: 1, total: 5)
        let truncated = ExpenseSearchResult(expenses: [Expense(name: "A", amount: 5)], matchCount: 3, total: 12.5)

        #expect(none.dialog(currencyCode: "USD") == "No expenses match that.")
        #expect(one.dialog(currencyCode: "USD") == "Found 1 expense totaling $5.00.")
        #expect(truncated.dialog(currencyCode: "USD") == "Found 3 expenses totaling $12.50. Here are 1 of them.")
    }
}

@Suite("Upcoming recurring expenses", .serialized)
struct UpcomingRecurringExpensesTests {
    private func rule(
        _ name: String, amount: Double = 10, frequency: RecurrenceFrequency, start: Date, end: Date? = nil
    ) -> RecurringExpenseRule {
        RecurringExpenseRule(
            name: name, amount: amount, note: "", category: .wants, frequency: frequency,
            startDate: start, endDate: end, recurrenceTimeZoneIdentifier: "America/Denver"
        )
    }

    @Test @MainActor
    func listsEveryOccurrenceInTheWindowSoonestFirst() throws {
        let store = try makeStore()
        let now = day(2026, 11, 4, hour: 9)
        store.context.insert(rule("Netflix", amount: 15.49, frequency: .monthly, start: day(2026, 10, 12)))
        store.context.insert(rule("Gym", amount: 20, frequency: .weekly, start: day(2026, 11, 6)))
        try store.save()

        let upcoming = try store.upcomingRecurringExpenses(within: 14, from: now, calendar: calendar)

        #expect(upcoming.map(\.name) == ["Gym", "Netflix", "Gym"])
        #expect(upcoming.map { calendar.component(.day, from: $0.date) } == [6, 12, 13])
    }

    @Test @MainActor
    func skipsEndedRulesAndCapsTheCount() throws {
        let store = try makeStore()
        let now = day(2026, 11, 4, hour: 9)
        store.context.insert(rule("Ended", frequency: .weekly, start: day(2026, 1, 1), end: day(2026, 10, 1)))
        store.context.insert(rule("Daily", frequency: .daily, start: day(2026, 11, 5)))
        try store.save()

        let upcoming = try store.upcomingRecurringExpenses(within: 365, from: now, calendar: calendar, limit: 10)

        #expect(upcoming.count == 10)
        #expect(upcoming.allSatisfy { $0.name == "Daily" })
    }

    @Test
    func dialogSummarizesTheWindow() {
        let date = day(2026, 11, 12)
        let netflix = UpcomingRecurringExpense(ruleID: UUID(), name: "Netflix", amount: 15.49, category: .wants, date: date)
        let gym = UpcomingRecurringExpense(ruleID: UUID(), name: "Gym", amount: 20, category: .wants, date: date)

        #expect(GetUpcomingRecurringExpensesIntent.dialog(for: [], days: 30, currencyCode: "USD")
                == "No recurring expenses are due in the next 30 days.")
        #expect(GetUpcomingRecurringExpensesIntent.dialog(for: [netflix], days: 1, currencyCode: "USD")
                == "One recurring expense is due in the next day: Netflix on Nov 12, for $15.49.")
        #expect(GetUpcomingRecurringExpensesIntent.dialog(for: [netflix, gym], days: 30, currencyCode: "USD")
                == "2 recurring expenses are due in the next 30 days, totaling $35.49. Next is Netflix on Nov 12.")
    }
}

@Suite("Expense sharing")
struct ExpenseShareTextTests {
    @Test @MainActor
    func shareTextReadsOnItsOwn() throws {
        let coffee = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
        let work = ExpenseTag(name: "Work", uiColor: .gray, emoji: "💼", symbolName: "briefcase")
        let expense = Expense(name: "Latte", amount: 5.25, category: .wants, date: day(2026, 11, 3),
                              tags: [coffee, work], note: "With Sam")

        let text = expense.entity.shareText
        let lines = text.split(separator: "\n").map(String.init)

        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Latte · "))
        #expect(lines[0].contains("· Wants · "))
        #expect(lines[0].contains("☕ Coffee"))
        #expect(lines[0].contains("Work") && !lines[0].contains("💼"))
        #expect(lines[1] == "With Sam")
        #expect(Expense(name: "Rent", amount: 900).entity.shareText.contains("\n") == false)
    }
}
