//
//  ExpenseCardView.swift
//  SageKit
//

import SwiftUI

struct ExpenseCardView: View {
    let expense: ExpenseEntity
    let colors: CategoryColors

    init(expense: ExpenseEntity, colors: CategoryColors = .load()) {
        self.expense = expense
        self.colors = colors
    }

    var body: some View {
        ExpenseRowView(expense, colors: colors)
            .snippetCard()
            .accessibilityElement(children: .combine)
    }
}

extension ExpenseRowView {
    init(_ expense: ExpenseEntity, colors: CategoryColors) {
        self.init(
            name: expense.name,
            amount: expense.amount.currencyString,
            date: expense.date.relative(),
            categoryName: expense.category.rawValue,
            categoryColor: colors.color(for: expense.category),
            glyph: expense.tags.first?.glyph,
            extraTagCount: max(expense.tags.count - 1, 0),
            isRecurring: expense.isRecurring
        )
    }
}

#Preview {
    let tag = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
    return ExpenseCardView(
        expense: Expense(name: "Latte", amount: 5.25, category: .wants, tags: [tag]).entity
    )
}
