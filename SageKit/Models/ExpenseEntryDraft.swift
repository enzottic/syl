import Foundation

/// Editable, unsaved values for a new expense. Duplicating an expense never copies its identity
/// or recurrence linkage. Keep this value in view state to bind wizard pages to one draft.
@MainActor
public struct ExpenseEntryDraft {
    public var name: String
    public var amount: Double?
    public var category: ExpenseCategory
    public var date: Date
    public var tags: [ExpenseTag]
    public var note: String
    public var isRecurring: Bool
    public var recurrenceFrequency: RecurrenceFrequency

    private let baseline: Snapshot

    public init(expense: Expense? = nil, now: Date = .now) {
        let initial = Snapshot(
            name: expense?.name ?? "",
            amount: expense?.amount,
            category: expense?.category ?? .needs,
            date: expense?.date ?? now,
            tagIDs: Set((expense?.tags ?? []).map(\.id)),
            note: expense?.note ?? "",
            isRecurring: false,
            recurrenceFrequency: .monthly
        )
        name = initial.name
        amount = initial.amount
        category = initial.category
        date = initial.date
        tags = expense?.tags ?? []
        note = initial.note
        isRecurring = initial.isRecurring
        recurrenceFrequency = initial.recurrenceFrequency
        baseline = initial
    }

    /// Compares with initialization, including duplication values. Tag order and tag metadata
    /// are not expense edits; selecting different tag identities is.
    public var hasChanges: Bool {
        Snapshot(
            name: name, amount: amount, category: category, date: date,
            tagIDs: Set(tags.map(\.id)), note: note, isRecurring: isRecurring,
            recurrenceFrequency: recurrenceFrequency
        ) != baseline
    }

    /// Validates without touching persistence and returns the unrounded amount to save.
    @discardableResult
    public func validate(currencyCode: String) throws -> Double {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.missingName
        }
        guard let amount,
              MonetaryAmount.isValid(amount, currencyCode: currencyCode, requiresPositive: isRecurring) else {
            throw ValidationError.invalidAmount(currencyCode: currencyCode, requiresPositive: isRecurring)
        }
        // Recurrence keys require a finite date representable at CloudKit's millisecond precision.
        guard date.timeIntervalSinceReferenceDate.isFinite,
              !isRecurring || RecurringExpenseOccurrence.safeMilliseconds(date) != nil else {
            throw ValidationError.invalidDate
        }
        return amount
    }

    public nonisolated enum ValidationError: LocalizedError, Equatable {
        case missingName
        case invalidAmount(currencyCode: String, requiresPositive: Bool)
        case invalidDate

        public var errorDescription: String? {
            switch self {
            case .missingName:
                "Please enter an expense name"
            case .invalidAmount(let currencyCode, let requiresPositive):
                MonetaryAmount.validationMessage(currencyCode: currencyCode, requiresPositive: requiresPositive)
            case .invalidDate:
                "Please enter a valid expense date"
            }
        }
    }

    private struct Snapshot: Equatable {
        let name: String
        let amount: Double?
        let category: ExpenseCategory
        let date: Date
        let tagIDs: Set<UUID>
        let note: String
        let isRecurring: Bool
        let recurrenceFrequency: RecurrenceFrequency
    }
}
