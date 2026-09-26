import Foundation
import SwiftData
import Testing
@testable import SageKit

@Suite("Expense suggestion history")
struct ExpenseSuggestionHistoryTests {
    @Test @MainActor
    func pagesPastRepeatedNamesToFindNewestDistinctMatches() throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let newest = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<40 {
            context.insert(Expense(name: "Coffee", amount: Double(index), date: newest.addingTimeInterval(Double(-index))))
        }
        context.insert(Expense(name: "Coffee Shop", amount: 10, date: newest.addingTimeInterval(-41)))
        context.insert(Expense(name: "Coffee Bar", amount: 8, date: newest.addingTimeInterval(-42)))
        try context.save()

        let matches = try ExpenseSuggestionHistory.recentDistinctMatches(for: "coffee", limit: 3, in: context)
        #expect(matches.map(\.name) == ["Coffee", "Coffee Shop", "Coffee Bar"])
        #expect(matches.first?.amount == 0)
    }

    @Test @MainActor
    func findsOlderTaggedExactMatchPastFirstPage() throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let newest = Date(timeIntervalSince1970: 1_800_000_000)
        let tag = ExpenseTag.dining
        context.insert(tag)
        for index in 0..<40 {
            context.insert(Expense(name: "Coffee", amount: 5, date: newest.addingTimeInterval(Double(-index))))
        }
        context.insert(Expense(name: "Coffee Shop", amount: 5, date: newest.addingTimeInterval(-40), tags: [tag]))
        context.insert(Expense(name: "Coffee", amount: 5, date: newest.addingTimeInterval(-41), tags: [tag]))
        try context.save()

        let match = try ExpenseSuggestionHistory.newestTaggedMatch(for: "COFFEE", in: context)
        #expect(match?.name == "Coffee")
        #expect(match?.tagName == tag.name)
    }
}
