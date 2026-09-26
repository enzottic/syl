import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Expense search predicate")
struct ExpenseSearchPredicateTests {
    @Test @MainActor
    func findsExpenseByTagName() throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let tag = ExpenseTag(name: "Groceries", uiColor: .blue, emoji: "🛒")
        let expense = Expense(name: "Market", amount: 20, tags: [tag])
        context.insert(tag)
        context.insert(expense)
        try context.save()

        let descriptor = ExpenseFetchDescriptors.search("Grocer", visibleLimit: 100)

        let matches = try context.fetch(descriptor)
        #expect(matches.map(\.id) == [expense.id])
    }

    @Test @MainActor
    func reachesOlderMatchesAcrossMultiplePages() throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let newestDate = Date.now
        var expected: [Expense] = []
        for index in 0..<205 {
            let expense = Expense(
                name: "Needle \(index)", amount: 1,
                date: newestDate.addingTimeInterval(Double(-index) * 86_400)
            )
            context.insert(expense)
            expected.append(expense)
        }
        context.insert(Expense(name: "Unrelated", amount: 1))
        try context.save()

        for limit in [100, 200, 300] {
            let matches = try context.fetch(ExpenseFetchDescriptors.search("Needle", visibleLimit: limit))
            #expect(matches.count == min(limit + 1, expected.count))
            #expect(matches.prefix(limit).map(\.id) == expected.prefix(limit).map(\.id))
            #expect((matches.count > limit) == (limit < expected.count))
        }
        let changedQuery = try context.fetch(ExpenseFetchDescriptors.search("Unrelated", visibleLimit: 100))
        #expect(changedQuery.map(\.name) == ["Unrelated"])
        #expect(try context.fetch(ExpenseFetchDescriptors.search("Missing", visibleLimit: 100)).isEmpty)
    }

    @Test @MainActor
    func exactPageHasNoExtraMatchAndReflectsDeletion() throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        for _ in 0..<100 {
            let expense = Expense(name: "Market", amount: 1)
            expense.note = "Needle in a note"
            context.insert(expense)
        }
        try context.save()
        let descriptor = ExpenseFetchDescriptors.search("Needle", visibleLimit: 100)
        let matches = try context.fetch(descriptor)
        #expect(matches.count == 100)
        context.delete(try #require(matches.first))
        try context.save()
        #expect(try context.fetch(descriptor).count == 99)
    }
}
