import SwiftData
import Foundation
import SwiftUI

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
