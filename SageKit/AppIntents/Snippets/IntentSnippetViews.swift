//
//  IntentSnippetViews.swift
//  SageKit
//

// Siri speaks a result's dialog but doesn't draw returned entities, so results supply these views.

import SwiftUI

struct ExpenseListSnippetView: View {
    static let visibleRowLimit = 6

    let expenses: [ExpenseEntity]
    /// Includes matches beyond those in `expenses`.
    let matchCount: Int
    let total: Double
    let colors: CategoryColors

    init(expenses: [ExpenseEntity], matchCount: Int, total: Double, colors: CategoryColors = .load()) {
        self.expenses = expenses
        self.matchCount = matchCount
        self.total = total
        self.colors = colors
    }

    var hiddenCount: Int { matchCount - min(expenses.count, Self.visibleRowLimit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SnippetHeader(
                title: matchCount == 1 ? "1 expense" : "\(matchCount) expenses",
                amount: total
            )
            ForEach(expenses.prefix(Self.visibleRowLimit), id: \.id) { expense in
                Divider()
                SnippetRow(
                    mark: expense.tags.first.map(SnippetMark.tag) ?? .dot,
                    color: colors.color(for: expense.category),
                    title: expense.name,
                    detail: "\(expense.date.formatted(date: .abbreviated, time: .omitted)) · \(expense.category.rawValue)",
                    amount: expense.amount
                )
            }
            if hiddenCount > 0 {
                Text("and \(hiddenCount) more")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct UpcomingExpensesSnippetView: View {
    let upcoming: [UpcomingRecurringExpense]
    let days: Int
    let colors: CategoryColors

    init(upcoming: [UpcomingRecurringExpense], days: Int, colors: CategoryColors = .load()) {
        self.upcoming = upcoming
        self.days = days
        self.colors = colors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SnippetHeader(
                title: days == 1 ? "Due in the next day" : "Due in the next \(days) days",
                amount: upcoming.reduce(0) { $0 + $1.amount }
            )
            if upcoming.isEmpty {
                Text("Nothing recurring is due.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(upcoming.prefix(ExpenseListSnippetView.visibleRowLimit).enumerated()), id: \.offset) { _, item in
                Divider()
                SnippetRow(
                    mark: .symbol("repeat"),
                    color: colors.color(for: item.category),
                    title: item.name,
                    detail: item.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                    amount: item.amount
                )
            }
            let hidden = upcoming.count - ExpenseListSnippetView.visibleRowLimit
            if hidden > 0 {
                Text("and \(hidden) more")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct AmountSummarySnippetView: View {
    let title: String
    let amount: Double
    let detail: String?
    /// Above 1 means over budget.
    let progress: Double?
    let tint: Color

    init(title: String, amount: Double, detail: String? = nil, progress: Double? = nil, tint: Color = .accentColor) {
        self.title = title
        self.amount = amount
        self.detail = detail
        self.progress = progress
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(amount.currencyString)
                .font(.largeTitle.weight(.semibold))
                .monospacedDigit()
            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(progress > 1 ? .red : tint)
                    .accessibilityLabel("\(Int((progress * 100).rounded())) percent of budget used")
            }
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

private struct SnippetHeader: View {
    let title: String
    let amount: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            Text(amount.currencyString)
                .font(.headline)
                .monospacedDigit()
        }
    }
}

enum SnippetMark {
    case tag(ExpenseTagEntity)
    case symbol(String)
    case dot
}

private struct SnippetRow: View {
    let mark: SnippetMark
    let color: Color
    let title: String
    let detail: String
    let amount: Double

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.2))
                switch mark {
                case .tag(let tag):
                    if let symbol = tag.symbolName { Image(systemName: symbol) } else { Text(tag.emoji) }
                case .symbol(let name):
                    Image(systemName: name).foregroundStyle(color)
                case .dot:
                    Circle().fill(color).frame(width: 8, height: 8)
                }
            }
            .font(.subheadline)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(amount.currencyString)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(amount < 0 ? Color.green : Color.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("List") {
    let tag = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
    let expenses = [
        Expense(name: "Latte", amount: 5.25, category: .wants, tags: [tag]),
        Expense(name: "Beans", amount: 18, category: .needs),
    ].map(\.entity)
    return ExpenseListSnippetView(expenses: expenses, matchCount: 9, total: 64.5)
}

#Preview("Summary") {
    AmountSummarySnippetView(title: "Left in your Wants budget", amount: 212.4,
                             detail: "$387.60 of $600.00 spent this month", progress: 0.646)
}
