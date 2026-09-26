import SwiftData
import Foundation
import SwiftUI

public enum SageSchemaV8: VersionedSchema {
    public static var versionIdentifier = Schema.Version(8, 0, 0)
    public static var models: [any PersistentModel.Type] = [Expense.self, ExpenseTag.self, RecurringExpenseRule.self, ExpenseAccount.self]

    @Model
    public final class Expense {
        #Index<Expense>([\.date], [\.recurringScheduledDate])

        public var id: UUID = UUID()
        public var name: String = "New Expense"
        public var amount: Double = 0.0
        public var category: ExpenseCategory = ExpenseCategory.needs
        // Index metadata alone does not trigger migration of an existing store.
        @Attribute(hashModifier: "expense-date-index-v8")
        public var date: Date = Date.now
        public var note: String = ""

        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.expenses)
        public var tag: ExpenseTag?
        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.taggedExpenses)
        public var tags: [ExpenseTag]? = []
        public var recurringExpenseId: UUID? = nil
        public var recurringOccurrenceKey: String? = nil
        /// Original occurrence date, independent of edits to the transaction date.
        public var recurringScheduledDate: Date? = nil
        @Relationship(deleteRule: .nullify, inverse: \ExpenseAccount.expenses)
        public var account: ExpenseAccount? = nil

        public init(name: String, amount: Double, category: ExpenseCategory = .wants, date: Date = .now, tag: ExpenseTag? = nil, tags: [ExpenseTag]? = nil, note: String = "", recurringExpenseId: UUID? = nil, recurringOccurrenceKey: String? = nil, account: ExpenseAccount? = nil) {
            self.id = UUID()
            self.name = name
            self.amount = amount
            self.category = category
            self.date = date
            self.tags = tags ?? tag.map { [$0] } ?? []
            self.note = note
            self.recurringExpenseId = recurringExpenseId
            self.recurringOccurrenceKey = recurringOccurrenceKey
            self.account = account
            backfillRecurringScheduledDate()
        }

        public func backfillRecurringScheduledDate() {
            guard recurringScheduledDate == nil, let ruleID = recurringExpenseId else { return }
            recurringScheduledDate = recurringOccurrenceKey.flatMap {
                RecurringExpenseOccurrence.scheduledDate(forKey: $0, ruleID: ruleID)
            } ?? date
        }
    }

    @Model
    public final class ExpenseTag: Identifiable {
        public var id: UUID = UUID()
        public var name: String = "Tag"
        public var emoji: String = "💰"
        public var symbolName: String? = nil
        @Attribute(.transformable(by: UIColorValueTransformer.self))
        public var uiColor: UIColor = UIColor.blue
        public var budget: Double? = nil
        @Relationship public var expenses: [Expense]?
        @Relationship public var recurringRules: [RecurringExpenseRule]?
        @Relationship public var taggedExpenses: [Expense]?
        @Relationship public var taggedRecurringRules: [RecurringExpenseRule]?

        public var color: Color { Color(uiColor: uiColor) }
        public var hasBudget: Bool { budget != nil }

        public init(id: UUID = UUID(), name: String, uiColor: UIColor, emoji: String, symbolName: String? = nil, budget: Double? = nil) {
            self.id = id
            self.name = name
            self.uiColor = uiColor
            self.emoji = emoji
            self.symbolName = symbolName
            self.budget = budget
        }
    }

    public enum RecurrenceFrequency: String, Codable, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case biweekly = "Bi-Weekly"
        case monthly = "Monthly"
    }

    @Model
    public final class RecurringExpenseRule: Identifiable {
        public var id: UUID = UUID()
        public var name: String = "New Expense"
        public var amount: Double = 0.0
        public var note: String = ""
        public var category: ExpenseCategory = ExpenseCategory.needs
        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.recurringRules)
        public var tag: ExpenseTag?
        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.taggedRecurringRules)
        public var tags: [ExpenseTag]? = []
        @Relationship(deleteRule: .nullify, inverse: \ExpenseAccount.recurringRules)
        public var account: ExpenseAccount?
        public var frequency: RecurrenceFrequency = RecurrenceFrequency.monthly
        public var startDate: Date = Date.now
        public var endDate: Date?
        public var lastGeneratedDate: Date?

        /// Nil preserves the legacy device-calendar schedule until the user confirms conversion.
        public var recurrenceTimeZoneIdentifier: String? = nil
        /// A durable forward-only boundary, independent of a potentially stale CloudKit cursor.
        public var recurrenceEffectiveDate: Date? = nil

        public init(name: String, amount: Double, note: String, category: ExpenseCategory, tag: ExpenseTag? = nil, tags: [ExpenseTag]? = nil, frequency: RecurrenceFrequency, startDate: Date, endDate: Date? = nil, lastGeneratedDate: Date? = nil, recurrenceTimeZoneIdentifier: String? = TimeZone.current.identifier) {
            self.id = UUID()
            self.name = name
            self.amount = amount
            self.note = note
            self.category = category
            self.tags = tags ?? tag.map { [$0] } ?? []
            self.frequency = frequency
            self.startDate = startDate
            self.endDate = endDate
            self.lastGeneratedDate = lastGeneratedDate
            self.recurrenceTimeZoneIdentifier = recurrenceTimeZoneIdentifier
        }
    }

    @Model
    public final class ExpenseAccount: Identifiable {
        public var id: UUID = UUID()
        public var name: String = "Account"
        public var type: AccountType = AccountType.bankAccount
        @Relationship public var expenses: [Expense]?
        @Relationship public var recurringRules: [RecurringExpenseRule]?

        public enum AccountType: String, Codable {
            case bankAccount = "Bank Account"
            case creditCard = "Credit Card"
            case other = "Other"
        }

        public init(id: UUID, name: String, type: AccountType) {
            self.id = id
            self.name = name
            self.type = type
        }
    }
}
