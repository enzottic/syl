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
