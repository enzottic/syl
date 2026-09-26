import Foundation
import WidgetKit
import SageKit

struct MonthlySummaryEntry: WidgetCurrencyEntry {
    let date: Date
    let totalSpent: Double
    let totalIncome: Int
    let wantsSpent: Double
    let wantsBudget: Double
    let needsSpent: Double
    let needsBudget: Double
    let savingsSpent: Double
    let savingsBudget: Double
    let recentExpenses: [ExpenseSnapshot]
    var isUnavailable = false
    var currencyCode: String? = LedgerCurrency.currentCode

    static let preview = MonthlySummaryEntry(
        date: .now, totalSpent: 3562.23, totalIncome: 7000,
        wantsSpent: 1045.32, wantsBudget: 2100,
        needsSpent: 2016.91, needsBudget: 3500,
        savingsSpent: 500.0, savingsBudget: 1400,
        recentExpenses: [
            ExpenseSnapshot(id: UUID(), name: "Groceries", amount: 87.43, category: .needs, date: .now),
            ExpenseSnapshot(id: UUID(), name: "Netflix", amount: 15.99, category: .wants, date: .now),
            ExpenseSnapshot(id: UUID(), name: "Savings Transfer", amount: 200.0, category: .savings, date: .now),
            ExpenseSnapshot(id: UUID(), name: "Electric Bill", amount: 94.00, category: .needs, date: .now),
            ExpenseSnapshot(id: UUID(), name: "Dinner Out", amount: 62.15, category: .wants, date: .now),
        ],
        currencyCode: "USD"
    )

    /// Spending with no income set, as after onboarding with $0 or Delete All Data.
    static let noIncomePreview = MonthlySummaryEntry(
        date: .now, totalSpent: 243.57, totalIncome: 0,
        wantsSpent: 62.15, wantsBudget: 0,
        needsSpent: 181.42, needsBudget: 0,
        savingsSpent: 0, savingsBudget: 0,
        recentExpenses: Array(preview.recentExpenses.prefix(2)),
        currencyCode: "USD"
    )
}
