import Foundation
import WidgetKit
import SageKit

struct RecentExpensesEntry: WidgetCurrencyEntry {
    let date: Date
    let expenses: [ExpenseSnapshot]
    var isUnavailable = false
    var currencyCode: String? = LedgerCurrency.currentCode

    static let preview = RecentExpensesEntry(date: .now, expenses: [
        ExpenseSnapshot(id: UUID(), name: "Groceries", amount: 87.43, category: .needs, date: .now),
        ExpenseSnapshot(id: UUID(), name: "Netflix", amount: 15.99, category: .wants, date: .now),
        ExpenseSnapshot(id: UUID(), name: "Savings Transfer", amount: 200.0, category: .savings, date: .now),
        ExpenseSnapshot(id: UUID(), name: "Electric Bill", amount: 94.00, category: .needs, date: .now),
        ExpenseSnapshot(id: UUID(), name: "Dinner Out", amount: 62.15, category: .wants, date: .now),
    ], currencyCode: "USD")
}
