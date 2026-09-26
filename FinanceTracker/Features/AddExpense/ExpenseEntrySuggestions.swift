import SwiftUI
import SageKit

struct ExpenseEntrySuggestions: View {
    let expenses: [Expense]
    let currencyCode: String
    let onSelect: (Expense) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(expenses) { expense in
                Button { onSelect(expense) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(expense.name)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(expense.amount.currencyString(code: currencyCode))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(12)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("past-expense-suggestion-\(expense.name)")
            }
        }
        .background(.cardBackground, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}
