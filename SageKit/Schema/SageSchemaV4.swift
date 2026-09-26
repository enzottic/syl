import SwiftData
import Foundation
import SwiftUI

public enum SageSchemaV4: VersionedSchema {
    public static var versionIdentifier = Schema.Version(4, 0, 0)
    public static var models: [any PersistentModel.Type] = [SageSchemaV4.Expense.self, SageSchemaV4.ExpenseTag.self, SageSchemaV4.RecurringExpenseRule.self, SageSchemaV4.ExpenseAccount.self]

    @Model
    public final class Expense {
        public var id: UUID = UUID()
        public var name: String = "New Expense"
        public var amount: Double = 0.0
        public var category: ExpenseCategory = ExpenseCategory.needs
        public var date: Date = Date.now
        public var note: String = ""

        /// Legacy single-tag relationship, retained for the V2→V3 lightweight migration and
        /// backfill. New code reads/writes `tags`; this is left nil for records created in V3+
        /// and can be removed in a future V5 once all installs have migrated.
        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.expenses)
        public var tag: ExpenseTag?

        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.taggedExpenses)
        public var tags: [ExpenseTag]? = []

        public var recurringExpenseId: UUID? = nil

        @Relationship(deleteRule: .nullify, inverse: \ExpenseAccount.expenses)
        public var account: ExpenseAccount? = nil

        public init(
            name: String,
            amount: Double,
            category: ExpenseCategory = .wants,
            date: Date = Date.now,
            tag: ExpenseTag? = nil,
            tags: [ExpenseTag]? = nil,
            note: String = "",
            recurringExpenseId: UUID? = nil,
            account: ExpenseAccount? = nil
        ) {
            self.id = UUID()
            self.name = name
            self.amount = amount
            self.category = category
            self.date = date
            self.tags = tags ?? tag.map { [$0] } ?? []
            self.note = note
            self.recurringExpenseId = recurringExpenseId
            self.account = account
        }
    }

    @Model
    public final class ExpenseTag: Identifiable {
        public var id: UUID = UUID()
        public var name: String = "Tag"
        public var emoji: String = "💰"

        /// SF Symbol name when the user picked an icon instead of an emoji; nil means render
        /// `emoji`. `emoji` stays populated either way, so string-only surfaces (Shortcuts
        /// titles, entity subtitles) always have something to show and switching back to the
        /// emoji tab in the picker doesn't lose the previous choice.
        public var symbolName: String? = nil

        @Attribute(.transformable(by: UIColorValueTransformer.self))
        public var uiColor: UIColor = UIColor.blue

        /// Optional monthly spending cap for this tag. `nil` — the default — means no budget is
        /// set and the tag is never reported as over/under budget. Independent of the expense's
        /// category, so a tag spanning needs and wants still has a single cap.
        public var budget: Double? = nil

        // Legacy single-tag inverses (see Expense.tag / RecurringExpenseRule.tag).
        @Relationship public var expenses: [Expense]?
        @Relationship public var recurringRules: [RecurringExpenseRule]?

        // Many-to-many inverses backing the new multi-tag relationships.
        @Relationship public var taggedExpenses: [Expense]?
        @Relationship public var taggedRecurringRules: [RecurringExpenseRule]?

        public var color: Color {
            Color(uiColor: uiColor)
        }

        /// Whether a spending cap has been set for this tag.
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

        // Fields gathered from the original expense to be copied to the new expense
        public var name: String = "New Expense"
        public var amount: Double = 0.0
        public var note: String = ""
        public var category: ExpenseCategory = ExpenseCategory.needs

        /// Legacy single-tag relationship (see `Expense.tag`).
        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.recurringRules)
        public var tag: ExpenseTag?

        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.taggedRecurringRules)
        public var tags: [ExpenseTag]? = []

        @Relationship(deleteRule: .nullify, inverse: \ExpenseAccount.recurringRules)
        public var account: ExpenseAccount?

        // Recurrance configuration
        public var frequency: RecurrenceFrequency = RecurrenceFrequency.monthly
        public var startDate: Date = Date.now
        public var endDate: Date?
        public var lastGeneratedDate: Date?

        public init(name: String, amount: Double, note: String, category: ExpenseCategory, tag: ExpenseTag? = nil, tags: [ExpenseTag]? = nil, frequency: RecurrenceFrequency, startDate: Date, endDate: Date? = nil, lastGeneratedDate: Date? = nil) {
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
