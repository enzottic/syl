//
//  WidgetTimelineEntry.swift
//  FinanceTracker
//
//  Created by Enzo on 10/7/25.
//

import Foundation
import WidgetKit
import SageKit

protocol WidgetCurrencyEntry: TimelineEntry {
    var currencyCode: String? { get }
}

extension WidgetCurrencyEntry {
    func currencyString(_ amount: Double) -> String {
        if let currencyCode {
            return amount.formatted(.currency(code: currencyCode))
        }
        return amount.formatted()
    }
}

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

struct CategorySpotlightEntry: WidgetCurrencyEntry {
    let date: Date
    let category: ExpenseCategory
    let spent: Double
    let budget: Double
    var isUnavailable = false
    var currencyCode: String? = LedgerCurrency.currentCode

    var utilization: Double { budget > 0 ? spent / budget : 0 }
    var remaining: Double { budget - spent }

    static func preview(category: ExpenseCategory) -> CategorySpotlightEntry {
        switch category {
        case .needs:   return CategorySpotlightEntry(date: .now, category: .needs, spent: 2016.91, budget: 3500, currencyCode: "USD")
        case .wants:   return CategorySpotlightEntry(date: .now, category: .wants, spent: 1045.32, budget: 2100, currencyCode: "USD")
        case .savings: return CategorySpotlightEntry(date: .now, category: .savings, spent: 500.0, budget: 1400, currencyCode: "USD")
        @unknown default:
            return CategorySpotlightEntry(date: .now, category: .needs, spent: 0, budget: 0, currencyCode: "USD")
        }
    }
}

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
}
