//
//  ExpenseCardView.swift
//  SageKit
//

import SwiftUI

/// The card Siri shows for an expense. The system renders it ahead of time into a static
/// archive, so it holds only text and images prepared from the entity.
struct ExpenseCardView: View {
    let expense: ExpenseEntity
    let categoryColor: Color

    init(expense: ExpenseEntity, colors: CategoryColors = .load()) {
        self.expense = expense
        self.categoryColor = colors.color(for: expense.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                mark
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(expense.date.formatted(date: .abbreviated, time: .omitted)) · \(expense.category.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(expense.amount.currencyString)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(expense.amount < 0 ? Color.green : Color.primary)
            }

            if !expense.tags.isEmpty || expense.isRecurring {
                HStack(spacing: 6) {
                    ForEach(expense.tags, id: \.id) { tag in
                        Label {
                            Text(tag.name)
                        } icon: {
                            tagMark(tag)
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(categoryColor.opacity(0.15), in: Capsule())
                    }
                    if expense.isRecurring {
                        Label("Recurring", systemImage: "repeat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }

            if !expense.note.isEmpty {
                Text(expense.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
    }

    /// The first tag's mark in the category's color, or a plain dot for an untagged expense.
    @ViewBuilder
    private var mark: some View {
        ZStack {
            Circle().fill(categoryColor.opacity(0.2))
            if let tag = expense.tags.first {
                tagMark(tag).font(.body)
            } else {
                Circle().fill(categoryColor).frame(width: 10, height: 10)
            }
        }
        .frame(width: 36, height: 36)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tagMark(_ tag: ExpenseTagEntity) -> some View {
        if let symbol = tag.symbolName {
            Image(systemName: symbol)
        } else {
            Text(tag.emoji)
        }
    }
}

#Preview {
    let tag = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
    return ExpenseCardView(
        expense: Expense(name: "Latte", amount: 5.25, category: .wants, tags: [tag], note: "With Sam").entity
    )
}
