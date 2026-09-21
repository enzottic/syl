//
//  CategoryUtilizationView.swift
//  FinanceTracker
//
//  Created by Enzo on 3/13/26.
//
import SwiftUI
import SageKit

struct CategoryUtilizationView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.categoryColors) private var categoryColors
    let category: ExpenseCategory
    let utilization: Double
    let used: Double
    let total: Double

    init(for category: ExpenseCategory, _ utilization: Double, _ used: Double, _ total: Double) {
        self.category = category
        self.utilization = utilization
        self.used = used
        self.total = total
    }

    var remaining: Double { max(total - used, 0) }
    var isOverBudget: Bool { used > total + 0.001 }

    var body: some View {
        HStack(spacing: 10) {
            CircularProgressBar(progress: utilization, tint: category.color(in: categoryColors))
                .frame(width: 50, height: 50)

            VStack(alignment: .leading) {
                Text(category.rawValue)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 5) {
                    Text(used.currencyString(code: config.ledgerCurrencyCode))
                        .fontWeight(.semibold)
                        .foregroundStyle(isOverBudget ? .red : .primary)
                    Text("of \(total.currencyString(code: config.ledgerCurrencyCode))")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(isOverBudget ? "-\((used - total).currencyString(code: config.ledgerCurrencyCode))" : "\(remaining.currencyString(code: config.ledgerCurrencyCode)) left")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isOverBudget ? .red : .secondary)
            }
        }
    }
}

#Preview {
    CategoryUtilizationView(for: .wants, 0.3, 100, 300)
        .environment(AppConfiguration.preview)
}
