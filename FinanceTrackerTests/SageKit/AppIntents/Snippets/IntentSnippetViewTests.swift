import Foundation
import SwiftUI
import Testing
import UIKit
@testable import SageKit

@Suite("Intent result cards")
struct IntentSnippetViewTests {
    private let colors = CategoryColors.default

    @Test
    func budgetSummaryDescribesEachStatus() {
        let under = BudgetSummary(status: .underBudget(remaining: 212.4), category: .wants, spent: 387.6, budget: 600)
        #expect(under.title == "Left in your Wants budget")
        #expect(under.amount == 212.4)
        #expect(abs((under.progress ?? 0) - 0.646) < 0.0001)

        let over = BudgetSummary(status: .overBudget(by: 50), category: nil, spent: 2_050, budget: 2_000)
        #expect(over.title == "Over your total budget")
        #expect(over.amount == 50)
        #expect((over.progress ?? 0) > 1)

        let saving = BudgetSummary(status: .belowTarget(remaining: 100), category: .savings, spent: 300, budget: 400)
        #expect(saving.title == "To go for your savings target")
        #expect(saving.detail?.hasSuffix("saved this month") == true)

        let reached = BudgetSummary(status: .targetReached, category: .savings, spent: 450, budget: 400)
        #expect(reached.title == "Saved this month")
        #expect(reached.amount == 450)

        let unset = BudgetSummary(status: .noBudget, category: .needs, spent: 80, budget: 0)
        #expect(unset.title == "Spent this month")
        #expect(unset.progress == nil)
        #expect(unset.detail == "No budget set")
    }

    @Test
    func spendingDetailListsCountThenFilters() {
        #expect(SpendingSummary.detail(count: 1, filters: [nil, nil]) == "1 expense")
        #expect(SpendingSummary.detail(count: 4, filters: ["Coffee", nil, "Wants"]) == "4 expenses · Coffee · Wants")
    }

    @Test @MainActor
    func listCardCountsRowsBeyondWhatItShows() {
        let expenses = (0..<9).map { Expense(name: "Item \($0)", amount: 1).entity }
        let shortList = ExpenseListSnippetView(expenses: Array(expenses.prefix(3)), matchCount: 3, total: 3, colors: colors)
        let longList = ExpenseListSnippetView(expenses: expenses, matchCount: 40, total: 40, colors: colors)

        #expect(shortList.hiddenCount == 0)
        #expect(longList.hiddenCount == 40 - ExpenseListSnippetView.visibleRowLimit)
    }

    @Test @MainActor
    func everyCardRenders() throws {
        let coffee = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
        let work = ExpenseTag(name: "Work", uiColor: .gray, emoji: "💼", symbolName: "briefcase")
        let tagged = Expense(name: "Latte", amount: 5.25, category: .wants, tags: [coffee, work], note: "With Sam").entity
        let refund = Expense(name: "Refund", amount: -12, category: .needs).entity
        let upcoming = [UpcomingRecurringExpense(ruleID: UUID(), name: "Netflix", amount: 15.49, category: .wants, date: .now)]

        let views: [AnyView] = [
            AnyView(ExpenseCardView(expense: tagged, colors: colors)),
            AnyView(ExpenseCardView(expense: refund, colors: colors)),
            AnyView(ExpenseListSnippetView(expenses: [tagged, refund], matchCount: 12, total: 99, colors: colors)),
            AnyView(UpcomingExpensesSnippetView(upcoming: upcoming, days: 30, colors: colors)),
            AnyView(AmountSummarySnippetView(title: "Spent this month", amount: 320, detail: "4 expenses", progress: 1.2)),
        ]
        for view in views {
            let renderer = ImageRenderer(content: view.frame(width: 360))
            let image = try #require(renderer.uiImage)
            #expect(image.size.height > 20)
        }
    }

    @Test @MainActor
    func emptyResultsDrawNoCard() {
        let views: [AnyView] = [
            AnyView(ExpenseListSnippetView(expenses: [], matchCount: 0, total: 0, colors: colors)),
            AnyView(UpcomingExpensesSnippetView(upcoming: [], days: 7, colors: colors)),
        ]
        for view in views {
            let size = ImageRenderer(content: view).uiImage?.size ?? .zero
            #expect(size.height == 0)
        }
    }

    @Test
    func tagMarksFollowTheAppsGlyphRule() {
        let symbolTag = ExpenseTag(name: "Dining", uiColor: .orange, emoji: "🍽️", symbolName: "fork.knife")
        let unknownSymbol = ExpenseTag(name: "Travel", uiColor: .blue, emoji: "✈️", symbolName: "not.a.real.symbol")
        let emojiTag = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")

        #expect(symbolTag.entity.symbolName == "fork.knife")
        #expect(symbolTag.entity.plainLabel == "Dining")
        #expect(unknownSymbol.entity.symbolName == nil)
        #expect(unknownSymbol.entity.plainLabel == "✈️ Travel")
        #expect(emojiTag.entity.plainLabel == "☕ Coffee")
    }
}
