//
//  ExpenseRowItem.swift
//  FinanceTracker
//
//  Created by Enzo on 10/4/25.
//

import SwiftUI
import SwiftData
import SageKit

struct ExpenseRowItem: View {
    typealias Style = ExpenseRowView.Style

    @Environment(\.relativeDateReference) private var referenceDate
    @Environment(\.categoryColors) private var categoryColors
    @Environment(AppConfiguration.self) private var config
    let expense: Expense
    var style: Style = .regular

    private var tags: [ExpenseTag] { expense.tags ?? [] }

    private var accessibilityDescription: String {
        var parts = [
            expense.name,
            expense.amount.currencyString(code: config.ledgerCurrencyCode),
            expense.category.rawValue,
            expense.date.relative(to: referenceDate)
        ]
        let tagNames = tags.filter { !$0.isDeleted }.map(\.name)
        if !tagNames.isEmpty {
            parts.append("Tags: \(tagNames.joined(separator: ", "))")
        }
        if expense.recurringExpenseId != nil {
            parts.append("Recurring expense")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        // A deleted expense's row can re-render during its removal animation,
        // after saving has detached the model and cleared its attributes.
        if expense.modelContext != nil && !expense.isDeleted {
            row
        }
    }

    private var row: some View {
        ExpenseRowView(
            name: expense.name,
            amount: expense.amount.currencyString(code: config.ledgerCurrencyCode),
            date: expense.date.relative(to: referenceDate),
            categoryName: expense.category.rawValue,
            categoryColor: expense.category.color(in: categoryColors),
            glyph: tags.first?.glyph,
            tagColor: config.expenseColorSource == .tag ? tags.first?.color : nil,
            extraTagCount: max(tags.count - 1, 0),
            isRecurring: expense.recurringExpenseId != nil,
            style: style
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}

#Preview {
    List {
        ExpenseRowItem(expense: Expense.example)
        ExpenseRowItem(expense: Expense.recurringExample)
    }
    .environment(AppConfiguration.preview)
}
