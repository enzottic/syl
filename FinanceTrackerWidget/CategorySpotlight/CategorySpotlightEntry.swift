import Foundation
import WidgetKit
import SageKit

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
