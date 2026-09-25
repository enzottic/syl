import Foundation
import SageKit
import SwiftData

public nonisolated struct RecurringExpenseRepairResult: Equatable, Sendable {
    public let backfilledCount: Int
    public let removedCount: Int

    public init(backfilledCount: Int = 0, removedCount: Int = 0) {
        self.backfilledCount = backfilledCount
        self.removedCount = removedCount
    }
}

@MainActor
public final class RecurringExpenseRepairService {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Backfills occurrence identities and keeps one generated expense per occurrence key.
    /// The caller owns the save so repair and generation can use one transaction.
    public func repair() throws -> RecurringExpenseRepairResult {
        let expenses = try modelContext.fetch(Self.recurringIdentityExpensesDescriptor())
        return repair(expenses: expenses)
    }

    static func recurringIdentityExpensesDescriptor() -> FetchDescriptor<Expense> {
        // Retain key-only records for the generation check, even when their rule ID was lost.
        FetchDescriptor<Expense>(predicate: #Predicate {
            $0.recurringExpenseId != nil || $0.recurringOccurrenceKey != nil
        })
    }

    /// Reuses the caller's recurring fetch when repair and generation run together.
    func repair(expenses: [Expense]) -> RecurringExpenseRepairResult {
        var groups: [String: [Expense]] = [:]
        var backfilledCount = 0

        for expense in expenses {
            guard let ruleID = expense.recurringExpenseId else { continue }

            // Older clients can sync records without the scheduled-date field after migration.
            expense.backfillRecurringScheduledDate()

            let key = expense.recurringOccurrenceKey
                ?? RecurringExpenseOccurrence.key(ruleID: ruleID, scheduledDate: expense.recurringScheduledDate ?? expense.date)

            if expense.recurringOccurrenceKey == nil {
                expense.recurringOccurrenceKey = key
                backfilledCount += 1
            }

            groups[key, default: []].append(expense)
        }

        var removedCount = 0

        for group in groups.values where group.count > 1 {
            // Every device chooses the same survivor, even when copies have different edits.
            let sorted = group.sorted { $0.id.uuidString < $1.id.uuidString }
            for duplicate in sorted.dropFirst() {
                modelContext.delete(duplicate)
                removedCount += 1
            }
        }

        return RecurringExpenseRepairResult(
            backfilledCount: backfilledCount,
            removedCount: removedCount
        )
    }
}
