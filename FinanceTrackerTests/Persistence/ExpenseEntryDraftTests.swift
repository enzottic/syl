import Foundation
import Testing
@testable import SageKit

@Suite("Expense entry draft")
@MainActor
struct ExpenseEntryDraftTests {
    @Test
    func newDraftUsesOneStableDateAndTracksRevertedEdits() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = ExpenseEntryDraft(now: date)
        #expect(draft.name.isEmpty)
        #expect(draft.amount == nil)
        #expect(draft.category == .needs)
        #expect(draft.date == date)
        #expect(draft.tags.isEmpty)
        #expect(draft.note.isEmpty)
        #expect(!draft.isRecurring)
        #expect(draft.recurrenceFrequency == .monthly)
        #expect(!draft.hasChanges)

        draft.note = "Remember this"
        #expect(draft.hasChanges)
        draft.note = ""
        #expect(!draft.hasChanges)
        draft.date = date.addingTimeInterval(1)
        #expect(draft.hasChanges)
        draft.date = date
        draft.recurrenceFrequency = .weekly
        #expect(draft.hasChanges)
        draft.recurrenceFrequency = .monthly
        #expect(!draft.hasChanges)
    }

    @Test
    func duplicationCopiesOldFormFieldsAndUsesThemAsBaseline() {
        let tag = ExpenseTag.dining
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let source = Expense(
            name: "Lunch", amount: 12.34, category: .wants, date: date,
            tags: [tag], note: "  Shared\nmeal  ", recurringExpenseId: UUID()
        )
        var draft = ExpenseEntryDraft(expense: source, now: date.addingTimeInterval(100))
        #expect(draft.name == source.name)
        #expect(draft.amount == source.amount)
        #expect(draft.category == source.category)
        #expect(draft.date == source.date)
        #expect(draft.tags.map(\.id) == [tag.id])
        #expect(draft.note == source.note)
        #expect(!draft.isRecurring)
        #expect(draft.recurrenceFrequency == .monthly)
        #expect(!draft.hasChanges)

        draft.name = "Dinner"
        #expect(draft.hasChanges)
        #expect(source.name == "Lunch")
        draft.name = source.name
        #expect(!draft.hasChanges)
        draft.amount = 20
        #expect(draft.hasChanges)
        draft.amount = source.amount
        draft.category = .savings
        #expect(draft.hasChanges)
        draft.category = source.category
        draft.isRecurring = true
        #expect(draft.hasChanges)
        draft.isRecurring = false
        #expect(!draft.hasChanges)
    }

    @Test
    func tagBaselineUsesSelectionIdentityNotOrderOrMutableMetadata() {
        let first = ExpenseTag.dining
        let second = ExpenseTag.shopping
        var draft = ExpenseEntryDraft(expense: Expense(name: "Meal", amount: 5, tags: [first, second]))
        first.name = "Renamed"
        draft.tags = [second, first, first]
        #expect(!draft.hasChanges)
        draft.tags = [second]
        #expect(draft.hasChanges)
        draft.tags = [first, second]
        #expect(!draft.hasChanges)
    }

    @Test
    func validationUsesLedgerMinorUnitsAndDoesNotNormalizeTextOrAmount() throws {
        var draft = ExpenseEntryDraft()
        draft.name = "  Refund  "
        draft.note = "  Original\nreceipt  "
        draft.amount = -12.34
        #expect(try draft.validate(currencyCode: "USD") == -12.34)
        #expect(draft.name == "  Refund  ")
        #expect(draft.note == "  Original\nreceipt  ")
        #expect(throws: ExpenseEntryDraft.ValidationError.invalidAmount(currencyCode: "JPY", requiresPositive: false)) {
            try draft.validate(currencyCode: "JPY")
        }
        draft.amount = 1.234
        #expect(try draft.validate(currencyCode: "KWD") == 1.234)
        draft.amount = 0.1 + 0.2
        #expect(try draft.validate(currencyCode: "USD") == 0.1 + 0.2)
    }
}
