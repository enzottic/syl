import Foundation
import SwiftData
import Testing
@testable import SageKit

@Suite("Stats expense queries")
struct StatsExpenseFetchDescriptorsTests {
    @Test @MainActor
    func boundsRecentAndOlderMonthWindowsWithoutLosingHistoryBars() throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let calendar = Self.calendar
        for (name, year, month) in [
            ("Older", 2024, 7), ("Old selection", 2025, 1),
            ("Recent history", 2025, 12), ("Selected", 2026, 5),
            ("Current", 2026, 9), ("Future", 2026, 10)
        ] {
            context.insert(Expense(name: name, amount: 1, date: try Self.date(year, month)))
        }
        try context.save()

        let current = try Self.date(2026, 9)
        let recent = try context.fetch(StatsExpenseFetchDescriptors.window(
            selectedMonth: Self.date(2026, 5), currentMonth: current, calendar: calendar
        ))
        #expect(Set(recent.map(\.name)) == ["Recent history", "Selected", "Current"])

        let older = try context.fetch(StatsExpenseFetchDescriptors.window(
            selectedMonth: Self.date(2025, 1), currentMonth: current, calendar: calendar
        ))
        #expect(Set(older.map(\.name)) == ["Older", "Old selection"])
    }

    @Test @MainActor
    func earliestExpenseRespectsCategoryAndTagFilters() throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let dining = ExpenseTag.dining
        let shopping = ExpenseTag.shopping
        context.insert(dining)
        context.insert(shopping)
        context.insert(Expense(name: "First", amount: 1, category: .needs,
                               date: try Self.date(2024, 1), tags: [dining]))
        context.insert(Expense(name: "Second", amount: 1, category: .wants,
                               date: try Self.date(2024, 7), tags: [dining]))
        context.insert(Expense(name: "Third", amount: 1, category: .needs,
                               date: try Self.date(2025, 1), tags: [shopping]))
        try context.save()

        #expect(try context.fetch(StatsExpenseFetchDescriptors.earliest(category: nil, tagID: nil)).first?.name == "First")
        #expect(try context.fetch(StatsExpenseFetchDescriptors.earliest(category: .wants, tagID: nil)).first?.name == "Second")
        #expect(try context.fetch(StatsExpenseFetchDescriptors.earliest(category: nil, tagID: shopping.id)).first?.name == "Third")
        #expect(try context.fetch(StatsExpenseFetchDescriptors.earliest(category: .wants, tagID: dining.id)).first?.name == "Second")
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: 1)))
    }
}
