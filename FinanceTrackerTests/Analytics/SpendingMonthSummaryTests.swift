import Foundation
import Testing
@testable import SageKit

@Suite("Spending month summary")
@MainActor
struct SpendingMonthSummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    @Test
    func currentCumulativeDaysStopTodayAndExcludeFutureRecords() throws {
        let start = try date(2026, 8, 1)
        let now = try date(2026, 8, 5, hour: 12)
        let expenses = [
            Expense(name: "Before month", amount: 999, date: start.addingTimeInterval(-1)),
            Expense(name: "Month start", amount: 10, category: .needs, date: start),
            Expense(name: "Third day", amount: 20, category: .wants, date: try date(2026, 8, 3)),
            Expense(name: "Exactly now", amount: 5, category: .needs, date: now),
            Expense(name: "Later today", amount: 999, date: now.addingTimeInterval(1)),
            Expense(name: "Tomorrow", amount: 999, date: try date(2026, 8, 6)),
            Expense(name: "Next month", amount: 999, date: try date(2026, 9, 1))
        ]

        let result = SpendingMonthSummary(month: start, expenses: expenses, now: now, calendar: calendar)

        #expect(result.expenses.map(\.name) == ["Month start", "Third day", "Exactly now"])
        #expect(result.total == 35)
        #expect(result.days.map(\.day) == Array(1...5))
        #expect(result.days.map(\.total) == [10, 10, 30, 30, 35])
        #expect(result.categoryDays[.needs]?.map(\.total) == [10, 10, 10, 10, 15])
        #expect(result.categoryDays[.wants]?.map(\.total) == [0, 0, 20, 20, 20])
        #expect(result.categoryDays[.savings]?.map(\.total) == [0, 0, 0, 0, 0])
    }

    @Test
    func completedMonthIncludesLastSecondButExcludesNextMonth() throws {
        let start = try date(2026, 8, 1)
        let end = try date(2026, 9, 1)
        let expenses = [
            Expense(name: "Month start", amount: 10, date: start),
            Expense(name: "Last second", amount: 20, date: end.addingTimeInterval(-1)),
            Expense(name: "Next month", amount: 999, date: end)
        ]

        let result = SpendingMonthSummary(month: start, expenses: expenses, now: end, calendar: calendar)

        #expect(result.expenses.map(\.name) == ["Month start", "Last second"])
        #expect(result.total == 30)
        #expect(result.days.map(\.day) == Array(1...31))
        #expect(result.days.map(\.total) == Array(repeating: 10.0, count: 30) + [30])
    }

    @Test
    func previousMonthComparisonUsesMatchingWallTime() throws {
        // March and February have different UTC offsets in this calendar.
        let now = try date(2026, 3, 15, hour: 12).addingTimeInterval(34 * 60 + 56)
        let cutoff = try date(2026, 2, 15, hour: 12).addingTimeInterval(34 * 60 + 56)
        let expenses = [
            Expense(name: "Before previous month", amount: 999, date: try date(2026, 1, 31)),
            Expense(name: "Previous month start", amount: 10, date: try date(2026, 2, 1)),
            Expense(name: "Matching day morning", amount: 20, date: try date(2026, 2, 15, hour: 9)),
            Expense(name: "Exactly at cutoff", amount: 5, date: cutoff),
            Expense(name: "After cutoff", amount: 999, date: cutoff.addingTimeInterval(1)),
            Expense(name: "Current spending", amount: 42, date: now)
        ]

        let result = SpendingMonthSummary(month: now, expenses: expenses, now: now, calendar: calendar)

        #expect(result.previousTotal == 35)
        #expect(result.total == 42)
    }

    @Test
    func completedMonthComparisonExcludesSelectedMonthMidnight() throws {
        let start = try date(2026, 8, 1)
        let expenses = [
            Expense(name: "Before previous month", amount: 999, date: try date(2026, 6, 30)),
            Expense(name: "Previous month start", amount: 10, date: try date(2026, 7, 1)),
            Expense(name: "Previous month last second", amount: 20, date: start.addingTimeInterval(-1)),
            Expense(name: "Selected month midnight", amount: 40, date: start)
        ]

        let result = SpendingMonthSummary(month: start, expenses: expenses,
                                          now: try date(2026, 9, 1), calendar: calendar)

        #expect(result.previousTotal == 30)
        #expect(result.total == 40)
    }

    @Test(arguments: [(2026, 28), (2024, 29)])
    func previousMonthComparisonClampsToShorterMonth(year: Int, lastDay: Int) throws {
        let now = try date(year, 3, 31, hour: 12)
        let expenses = [
            Expense(name: "February start", amount: 10, date: try date(year, 2, 1)),
            Expense(name: "February last second", amount: 20,
                    date: try date(year, 2, lastDay, hour: 23).addingTimeInterval(3599)),
            Expense(name: "March midnight", amount: 40, date: try date(year, 3, 1)),
            Expense(name: "March second day", amount: 50, date: try date(year, 3, 2))
        ]

        let result = SpendingMonthSummary(month: now, expenses: expenses, now: now, calendar: calendar)

        #expect(result.previousTotal == 30)
        #expect(result.total == 90)
    }

    @Test
    func refundsRemainSignedInTotalsAndCumulativeCurves() throws {
        let now = try date(2026, 8, 3, hour: 12)
        let expenses = [
            Expense(name: "Purchase", amount: 20.25, category: .needs, date: try date(2026, 8, 1)),
            Expense(name: "Refund", amount: -5.25, category: .needs, date: try date(2026, 8, 1, hour: 12)),
            Expense(name: "Refund only day", amount: -25, category: .wants, date: try date(2026, 8, 2)),
            Expense(name: "Prior purchase", amount: 8, date: try date(2026, 7, 1)),
            Expense(name: "Prior refund", amount: -20, date: try date(2026, 7, 2))
        ]

        let result = SpendingMonthSummary(month: now, expenses: expenses, now: now, calendar: calendar)

        #expect(result.total == -10)
        #expect(result.days.map(\.total) == [15, -10, -10])
        #expect(result.categoryDays[.needs]?.map(\.total) == [15, 15, 15])
        #expect(result.categoryDays[.wants]?.map(\.total) == [0, -25, -25])
        #expect(result.previousTotal == -12)
        #expect(result.historicalMonthCount == 1)
        #expect(result.averageDays.map(\.total) == [8] + Array(repeating: -12.0, count: 30))
    }

    @Test
    func historicalAverageIncludesGapsButNotMonthsBeforeFirstRecord() throws {
        let now = try date(2026, 7, 4, hour: 12)
        let expenses = [
            Expense(name: "First record", amount: 40, date: try date(2026, 3, 2)),
            Expense(name: "After April gap", amount: 80, date: try date(2026, 5, 4)),
            Expense(name: "Selected month", amount: 999, date: try date(2026, 7, 1))
        ]

        let result = SpendingMonthSummary(month: now, expenses: expenses, now: now, calendar: calendar)

        // March through June count, including empty April and June; January and February do not.
        #expect(result.historicalMonthCount == 4)
        #expect(result.averageDays.map(\.day) == Array(1...31))
        #expect(result.averageDays.map(\.total) == [0, 10, 10] + Array(repeating: 30.0, count: 28))
    }

    @Test
    func historicalAverageUsesOnlySixMostRecentCompleteMonths() throws {
        let now = try date(2026, 8, 5, hour: 12)
        var expenses = [Expense(name: "Too old", amount: 999, date: try date(2026, 1, 1))]
        for month in 2...7 {
            expenses.append(Expense(name: "Historical month", amount: 12, date: try date(2026, month, 1)))
        }
        expenses.append(Expense(name: "Current month", amount: 999, date: try date(2026, 8, 1)))

        let result = SpendingMonthSummary(month: now, expenses: expenses, now: now, calendar: calendar)

        #expect(result.historicalMonthCount == 6)
        #expect(result.averageDays.map(\.day) == Array(1...31))
        #expect(result.averageDays.map(\.total) == Array(repeating: 12.0, count: 31))
    }

    @Test
    func boundedHistoryWithFirstRecordedDateMatchesFullLedgerAverage() throws {
        let now = try date(2026, 9, 10, hour: 12)
        let first = Expense(name: "First record", amount: 25, date: try date(2020, 1, 1))
        let recent = Expense(name: "Recent", amount: 30, date: try date(2026, 7, 5))
        let selected = Expense(name: "Selected", amount: 40, date: try date(2026, 9, 2))
        let full = SpendingMonthSummary(month: now, expenses: [first, recent, selected],
                                        now: now, calendar: calendar)
        let bounded = SpendingMonthSummary(month: now, expenses: [recent, selected],
                                           firstRecordedDate: first.date, now: now, calendar: calendar)

        #expect(bounded.total == full.total)
        #expect(bounded.previousTotal == full.previousTotal)
        #expect(bounded.days.map(\.total) == full.days.map(\.total))
        #expect(bounded.historicalMonthCount == full.historicalMonthCount)
        #expect(bounded.averageDays.map(\.total) == full.averageDays.map(\.total))
    }

    @Test(arguments: [(2026, 28), (2024, 29)])
    func shorterHistoricalMonthCarriesFinalTotalForward(year: Int, lastDay: Int) throws {
        let now = try date(year, 3, 2, hour: 12)
        let expenses = [
            Expense(name: "February start", amount: 10, date: try date(year, 2, 1)),
            Expense(name: "February end", amount: 20, date: try date(year, 2, lastDay, hour: 23))
        ]

        let result = SpendingMonthSummary(month: now, expenses: expenses, now: now, calendar: calendar)

        #expect(result.historicalMonthCount == 1)
        #expect(result.averageDays.map(\.day) == Array(1...31))
        #expect(result.averageDays.map(\.total) == Array(repeating: 10.0, count: lastDay - 1)
            + Array(repeating: 30.0, count: 32 - lastDay))
    }
}
