import Foundation
import SwiftData
import Testing
@testable import SageKit

@Suite("Preview fixtures", .serialized)
struct PreviewFixturesTests {
    #if DEBUG
    @Test @MainActor
    func richPreviewPreservesExistingSettings() throws {
        let defaults = UserDefaults.standard
        let sentinels: [String: NSNumber] = [
            "totalMonthlyIncome": 8765,
            "needsPercent": 0.41,
            "wantsPercent": 0.32,
            "savingsPercent": 0.27,
            "hasOpenedAppOnce": false,
        ]
        let originalValues = sentinels.keys.map { (key: $0, value: defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        for (key, value) in sentinels {
            defaults.set(value, forKey: key)
        }

        let container = try SageModelContainer.makePreview()

        for (key, value) in sentinels {
            #expect(defaults.object(forKey: key) as? NSNumber == value, "Preview changed \(key)")
        }
        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count > 100)
        #expect(Set(expenses.map(\.category)) == [.needs, .wants, .savings])
        #expect(expenses.contains { !($0.tags ?? []).isEmpty })
    }
    #endif

    @Test @MainActor
    func recurringPreviewsAreIndependentAndUpcoming() throws {
        let first = try SageModelContainer.makeRecurringPreview()
        let second = try SageModelContainer.makeRecurringPreview()
        let now = Date.now
        let horizon = try #require(Calendar.current.date(byAdding: .day, value: 30, to: now))
        let firstRules = try first.mainContext.fetch(FetchDescriptor<RecurringExpenseRule>())
        let secondRules = try second.mainContext.fetch(FetchDescriptor<RecurringExpenseRule>())
        let secondIDs = Set(secondRules.map(\.id))
        #expect(!firstRules.isEmpty)
        #expect(firstRules.count == secondRules.count)
        #expect(Set(firstRules.map(\.id)).isDisjoint(with: secondIDs))

        for container in [first, second] {
            #expect(try container.mainContext.fetchCount(FetchDescriptor<Expense>()) == 0)
            let rules = try container.mainContext.fetch(FetchDescriptor<RecurringExpenseRule>())
            for rule in rules {
                let next = try #require(rule.nextOccurrence(after: now))
                #expect(next > now && next <= horizon)
                #expect(rule.modelContext === container.mainContext)
            }
        }

        first.mainContext.delete(try #require(firstRules.first))
        try first.mainContext.save()
        let remaining = try ModelContext(second).fetch(FetchDescriptor<RecurringExpenseRule>())
        #expect(Set(remaining.map(\.id)) == secondIDs)
    }
}
