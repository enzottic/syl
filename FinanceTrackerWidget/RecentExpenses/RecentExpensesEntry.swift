import Foundation
import SwiftUI
import WidgetKit
import SageKit

struct RecentExpensesEntry: WidgetCurrencyEntry {
    let date: Date
    let expenses: [ExpenseSnapshot]
    var todayTotal: Double = 0
    var isUnavailable = false
    var currencyCode: String? = LedgerCurrency.currentCode

    static let preview = RecentExpensesEntry(date: .now, expenses: [
        ExpenseSnapshot(id: UUID(), name: "Groceries", amount: 87.43, category: .needs, date: .now,
                        glyph: .symbol("basket.fill"), tagColor: .green),
        ExpenseSnapshot(id: UUID(), name: "Netflix", amount: 15.99, category: .wants, date: .now,
                        glyph: .symbol("play.rectangle.fill"), tagColor: .teal),
        ExpenseSnapshot(id: UUID(), name: "Savings Transfer", amount: 200.0, category: .savings,
                        date: .now.addingTimeInterval(-86_400)),
    ], todayTotal: 103.42, currencyCode: "USD")
}
