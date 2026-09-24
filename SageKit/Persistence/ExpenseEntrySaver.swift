import Foundation
import SwiftData

/// Saves a new expense without committing or rolling back another context's pending edits.
/// The caller owns presentation, widget refreshes, and success/error notifications.
@MainActor
public struct ExpenseEntrySaver {
    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Returns the saved expense's UUID, rather than a model bound to the private context.
    /// Selected tags must already be persisted in this container. A missing or ambiguous tag
    /// fails the entire save rather than silently changing the user's selection.
    /// The save closure is a test seam; it must perform one atomic context save or throw.
    @discardableResult
    public func save(
        _ draft: ExpenseEntryDraft,
        currencyCode: String,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> UUID {
        let amount = try draft.validate(currencyCode: currencyCode)
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        do {
            var seenTagIDs = Set<UUID>()
            let tags = try draft.tags.compactMap { selected -> ExpenseTag? in
                let id = selected.id
                guard seenTagIDs.insert(id).inserted else { return nil }
                let matches = try context.fetch(FetchDescriptor<ExpenseTag>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard let tag = matches.first else { throw SaveError.missingTag(id) }
                guard matches.count == 1 else { throw SaveError.ambiguousTag(id) }
                return tag
            }

            var recurringID: UUID?
            var occurrenceKey: String?
            if draft.isRecurring {
                let rule = RecurringExpenseRule(
                    name: draft.name,
                    amount: amount,
                    note: draft.note,
                    category: draft.category,
                    tags: tags,
                    frequency: draft.recurrenceFrequency,
                    startDate: draft.date,
                    lastGeneratedDate: draft.date
                )
                recurringID = rule.id
                occurrenceKey = RecurringExpenseOccurrence.key(ruleID: rule.id, scheduledDate: draft.date)
                context.insert(rule)
            }

            // Expense derives its immutable scheduled date from the occurrence key.
            let expense = Expense(
                name: draft.name,
                amount: amount,
                category: draft.category,
                date: draft.date,
                tags: tags,
                note: draft.note,
                recurringExpenseId: recurringID,
                recurringOccurrenceKey: occurrenceKey
            )
            context.insert(expense)
            try save(context)
            return expense.id
        } catch {
            context.rollback()
            throw error
        }
    }

    public nonisolated enum SaveError: LocalizedError, Equatable {
        case missingTag(UUID)
        case ambiguousTag(UUID)

        public var errorDescription: String? {
            switch self {
            case .missingTag:
                "A selected tag is no longer available. Review your tags and try again."
            case .ambiguousTag:
                "More than one saved tag has the same identity. Review your tags and try again."
            }
        }
    }
}
