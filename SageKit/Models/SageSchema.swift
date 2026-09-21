//
//  SageSchema.swift
//  FinanceTracker
//
//  Created by Tyler McCormick on 3/7/26.
//
import SwiftData
import Foundation
import SwiftUI

public enum SageSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] = [SageSchemaV1.Expense.self, SageSchemaV1.ExpenseTag.self, SageSchemaV1.RecurringExpenseRule.self]
    
    @Model
    public final class Expense {
        public var id: UUID = UUID()
        var name: String = "New Expense"
        var amount: Double = 0.0
        var category: ExpenseCategory = ExpenseCategory.needs
        var date: Date = Date.now
        var note: String = ""
        
        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.expenses)
        var tag: ExpenseTag?
        
        var recurringExpenseId: UUID? = nil
        
        init(
            name: String,
            amount: Double,
            category: ExpenseCategory = .wants,
            date: Date = Date.now,
            tag: ExpenseTag? = nil,
            note: String = "",
            recurringExpenseId: UUID? = nil,
        ) {
            self.id = UUID()
            self.name = name
            self.amount = amount
            self.category = category
            self.date = date
            self.tag = tag
            self.note = note
            self.recurringExpenseId = recurringExpenseId
        }
    }
    
    @Model
    public final class ExpenseTag: Identifiable {
        public var id: UUID = UUID()
        var name: String = "Tag"
        var emoji: String = "💰"
        
        @Attribute(.transformable(by: UIColorValueTransformer.self))
        var uiColor: UIColor = UIColor.blue
        
        @Relationship var expenses: [Expense]?
        @Relationship var recurringRules: [RecurringExpenseRule]?
        
        var color: Color {
            Color(uiColor: uiColor)
        }
        
        init(id: UUID = UUID(), name: String, uiColor: UIColor, emoji: String) {
            self.id = id
            self.name = name
            self.uiColor = uiColor
            self.emoji = emoji
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
        var name: String = "My Expense"
        var amount: Double = 0.0
        var note: String = ""
        var category: ExpenseCategory = ExpenseCategory.wants
        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.recurringRules)
        var tag: ExpenseTag?
        
        var frequency: RecurrenceFrequency = RecurrenceFrequency.monthly
        var startDate: Date = Date.now
        var endDate: Date?
        var lastGeneratedDate: Date?
        
        init(name: String, amount: Double, note: String, category: ExpenseCategory, tag: ExpenseTag, frequency: RecurrenceFrequency, startDate: Date, endDate: Date? = nil, lastGeneratedDate: Date? = nil) {
            self.id = UUID()
            self.name = name
            self.amount = amount
            self.note = note
            self.category = category
            self.tag = tag
            self.frequency = frequency
            self.startDate = startDate
            self.endDate = endDate
            self.lastGeneratedDate = lastGeneratedDate
        }
    }
    
}

public enum SageSchemaV2: VersionedSchema {
    public static var versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] = [SageSchemaV2.Expense.self, SageSchemaV2.ExpenseTag.self, SageSchemaV2.RecurringExpenseRule.self, SageSchemaV2.ExpenseAccount.self]
    
    @Model
    public final class Expense {
        public var id: UUID = UUID()
        public var name: String = "New Expense"
        public var amount: Double = 0.0
        public var category: ExpenseCategory = ExpenseCategory.needs
        public var date: Date = Date.now
        public var note: String = ""
        
        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.expenses)
        public var tag: ExpenseTag?
        
        public var recurringExpenseId: UUID? = nil
        
        @Relationship(deleteRule: .nullify, inverse: \ExpenseAccount.expenses)
        public var account: ExpenseAccount? = nil
        
        public init(
            name: String,
            amount: Double,
            category: ExpenseCategory = .wants,
            date: Date = Date.now,
            tag: ExpenseTag? = nil,
            note: String = "",
            recurringExpenseId: UUID? = nil,
            account: ExpenseAccount? = nil
        ) {
            self.id = UUID()
            self.name = name
            self.amount = amount
            self.category = category
            self.date = date
            self.tag = tag
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
        
        @Attribute(.transformable(by: UIColorValueTransformer.self))
        public var uiColor: UIColor = UIColor.blue
        
        @Relationship public var expenses: [Expense]?
        @Relationship public var recurringRules: [RecurringExpenseRule]?
        
        public var color: Color {
            Color(uiColor: uiColor)
        }
        
        public init(id: UUID = UUID(), name: String, uiColor: UIColor, emoji: String) {
            self.id = id
            self.name = name
            self.uiColor = uiColor
            self.emoji = emoji
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
        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.recurringRules)
        public var tag: ExpenseTag?
        
        @Relationship(deleteRule: .nullify, inverse: \ExpenseAccount.recurringRules)
        public var account: ExpenseAccount?
        
        // Recurrance configuration
        public var frequency: RecurrenceFrequency = RecurrenceFrequency.monthly
        public var startDate: Date = Date.now
        public var endDate: Date?
        public var lastGeneratedDate: Date?
        
        public init(name: String, amount: Double, note: String, category: ExpenseCategory, tag: ExpenseTag? = nil, frequency: RecurrenceFrequency, startDate: Date, endDate: Date? = nil, lastGeneratedDate: Date? = nil) {
            self.id = UUID()
            self.name = name
            self.amount = amount
            self.note = note
            self.category = category
            self.tag = tag
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

public enum SageSchemaV3: VersionedSchema {
    public static var versionIdentifier = Schema.Version(3, 0, 0)
    public static var models: [any PersistentModel.Type] = [SageSchemaV3.Expense.self, SageSchemaV3.ExpenseTag.self, SageSchemaV3.RecurringExpenseRule.self, SageSchemaV3.ExpenseAccount.self]

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
        /// and can be removed in a future V4 once all installs have migrated.
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

        public init(id: UUID = UUID(), name: String, uiColor: UIColor, emoji: String, budget: Double? = nil) {
            self.id = id
            self.name = name
            self.uiColor = uiColor
            self.emoji = emoji
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

public enum SageSchemaV5: VersionedSchema {
    public static var versionIdentifier = Schema.Version(5, 0, 0)
    public static var models: [any PersistentModel.Type] = [SageSchemaV5.Expense.self, SageSchemaV5.ExpenseTag.self, SageSchemaV5.RecurringExpenseRule.self, SageSchemaV5.ExpenseAccount.self]

    @Model
    public final class Expense {
        public var id: UUID = UUID()
        public var name: String = "New Expense"
        public var amount: Double = 0.0
        public var category: ExpenseCategory = ExpenseCategory.needs
        public var date: Date = Date.now
        public var note: String = ""

        /// Legacy single-tag relationship retained for migration support.
        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.expenses)
        public var tag: ExpenseTag?

        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.taggedExpenses)
        public var tags: [ExpenseTag]? = []

        public var recurringExpenseId: UUID? = nil

        /// Stable identity for one scheduled occurrence of a recurring rule.
        /// This stays unchanged when the user edits the expense date.
        public var recurringOccurrenceKey: String? = nil

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
            recurringOccurrenceKey: String? = nil,
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
            self.recurringOccurrenceKey = recurringOccurrenceKey
            self.account = account
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

        public var color: Color {
            Color(uiColor: uiColor)
        }

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

public enum SageSchemaV6: VersionedSchema {
    public static var versionIdentifier = Schema.Version(6, 0, 0)
    public static var models: [any PersistentModel.Type] = [Expense.self, ExpenseTag.self, RecurringExpenseRule.self, ExpenseAccount.self]

    @Model
    public final class Expense {
        public var id: UUID = UUID()
        public var name: String = "New Expense"
        public var amount: Double = 0.0
        public var category: ExpenseCategory = ExpenseCategory.needs
        public var date: Date = Date.now
        public var note: String = ""

        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.expenses)
        public var tag: ExpenseTag?
        @Relationship(deleteRule: .nullify, inverse: \ExpenseTag.taggedExpenses)
        public var tags: [ExpenseTag]? = []
        public var recurringExpenseId: UUID? = nil
        public var recurringOccurrenceKey: String? = nil
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

public enum SageSchemaV7: VersionedSchema {
    public static var versionIdentifier = Schema.Version(7, 0, 0)
    public static var models: [any PersistentModel.Type] = [Expense.self, ExpenseTag.self, RecurringExpenseRule.self, ExpenseAccount.self]

    @Model
    public final class Expense {
        #Index<Expense>([\.recurringScheduledDate])

        public var id: UUID = UUID()
        public var name: String = "New Expense"
        public var amount: Double = 0.0
        public var category: ExpenseCategory = ExpenseCategory.needs
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

public enum SageSchemaV9: VersionedSchema {
    public static var versionIdentifier = Schema.Version(9, 0, 0)
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
        public var isHiddenFromExpenseEntry: Bool = false
        
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


public class SageSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] = [SageSchemaV1.self, SageSchemaV2.self, SageSchemaV3.self, SageSchemaV4.self, SageSchemaV5.self, SageSchemaV6.self, SageSchemaV7.self, SageSchemaV8.self, SageSchemaV9.self]

    public static var stages: [MigrationStage] = [
        MigrationStage.lightweight(fromVersion: SageSchemaV1.self, toVersion: SageSchemaV2.self),
        MigrationStage.lightweight(fromVersion: SageSchemaV2.self, toVersion: SageSchemaV3.self),
        MigrationStage.lightweight(fromVersion: SageSchemaV3.self, toVersion: SageSchemaV4.self),
        MigrationStage.lightweight(fromVersion: SageSchemaV4.self, toVersion: SageSchemaV5.self),
        MigrationStage.lightweight(fromVersion: SageSchemaV5.self, toVersion: SageSchemaV6.self),
        MigrationStage.custom(fromVersion: SageSchemaV6.self, toVersion: SageSchemaV7.self, willMigrate: nil) { context in
            let expenses = try context.fetch(FetchDescriptor<SageSchemaV7.Expense>(
                predicate: #Predicate { $0.recurringExpenseId != nil }
            ))
            for expense in expenses {
                expense.backfillRecurringScheduledDate()
            }
            try context.save()
        },
        MigrationStage.lightweight(fromVersion: SageSchemaV7.self, toVersion: SageSchemaV8.self),
        MigrationStage.lightweight(fromVersion: SageSchemaV8.self, toVersion: SageSchemaV9.self)
    ]
}

public extension Expense {
    static var example: Expense = Expense(name: "Car Insurance", amount: 123.43, category: .needs, date: .now, tag: .billsAndUtils, note: "Progressive Insurance", recurringExpenseId: nil, account: nil)
    static var recurringExpense: RecurringExpenseRule = RecurringExpenseRule(name: "Rent", amount: 1300.00, note: "Rent", category: .needs, tag: .billsAndUtils, frequency: .monthly, startDate: .now)
    static var recurringExample: Expense = Expense(name: "Rent", amount: 1300.00,  category: .needs, date: .now, tag: .billsAndUtils, note: "Rent", recurringExpenseId: recurringExpense.id, account: nil)
}

public struct ExpenseSnapshot: Identifiable {
    public let id: UUID
    public let name: String
    public let amount: Double
    public let category: ExpenseCategory
    public let date: Date

    public init(id: UUID, name: String, amount: Double, category: ExpenseCategory, date: Date) {
        self.id = id
        self.name = name
        self.amount = amount
        self.category = category
        self.date = date
    }
}

public extension [Expense] {
    var total: Double {
        self.reduce(0) { $0 + $1.amount }
    }
    
    var wantsUsed: Double {
        self.filter { $0.category == .wants }
            .reduce(0) { $0 + $1.amount }
    }
    
    var needsUsed: Double {
        self.filter { $0.category == .needs}
            .reduce(0) { $0 + $1.amount }
    }
    
    var savingsUsed: Double {
        self.filter { $0.category == .savings}
            .reduce(0) { $0 + $1.amount }
    }

    /// Total spent against `tag` within the calendar month containing `month`.
    /// Counts an expense once if it carries the tag, regardless of its category.
    func monthlyTotal(for tag: ExpenseTag, in month: Date = .now, calendar: Calendar = .current) -> Double {
        self.filter { expense in
            calendar.isDate(expense.date, equalTo: month, toGranularity: .month)
                && (expense.tags ?? []).contains { $0.id == tag.id }
        }
        .reduce(0) { $0 + $1.amount }
    }
}

public typealias Expense = SageSchemaV9.Expense
public typealias ExpenseTag = SageSchemaV9.ExpenseTag
public typealias RecurringExpenseRule = SageSchemaV9.RecurringExpenseRule
public typealias RecurrenceFrequency = SageSchemaV9.RecurrenceFrequency
public typealias ExpenseAccount = SageSchemaV9.ExpenseAccount
