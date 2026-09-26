import SwiftUI
import SageKit

struct DailySpendingDetails: View {
    enum Style {
        case topExpenses
        case allExpenses
    }

    @Environment(AppConfiguration.self) private var config

    let date: Date
    let total: Double
    let expenses: [Expense]
    var upcomingExpenses: [SpendingCalendarMonth.UpcomingExpense] = []
    var category: ExpenseCategory? = nil
    var isFuture = false
    var style: Style = .allExpenses
    let accessibilityPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(date.formatted(.dateTime.month(.wide).day()))
                    .font(.subheadline.weight(.semibold))
                if let category {
                    Text(category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                Text("\(total.currencyString(code: config.ledgerCurrencyCode)) \(isFuture ? "expected this day" : "spent this day")")
                    .font(.headline)
                    .monospacedDigit()
                    .accessibilityIdentifier("\(accessibilityPrefix)-total")
            }
            if style == .allExpenses {
                ViewThatFits(in: .vertical) {
                    expenseList
                    ScrollView { expenseList }
                }
                .frame(maxHeight: 260)
            } else {
                expenseList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(accessibilityPrefix)-details")
    }

    private var expenseList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if expenses.isEmpty && upcomingExpenses.isEmpty {
                Text(isFuture ? "No upcoming expenses for this day." : "No expenses recorded for this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !expenses.isEmpty {
                Text(style == .topExpenses ? "Top Expenses" : "Recorded Expenses")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(expenses.prefix(style == .topExpenses ? 3 : expenses.count))) { expense in
                    ExpenseDetailRow(name: expense.name, amount: expense.amount, category: expense.category,
                                     nameLineLimit: style == .topExpenses ? 2 : nil)
                }
            }
            if !upcomingExpenses.isEmpty {
                Text("Upcoming Expenses").font(.caption).foregroundStyle(.secondary)
                ForEach(upcomingExpenses) { expense in
                    ExpenseDetailRow(name: expense.name, amount: expense.amount, category: expense.category)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
