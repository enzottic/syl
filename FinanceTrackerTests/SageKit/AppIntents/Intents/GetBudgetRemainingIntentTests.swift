import Foundation
import SwiftData
import Testing
@testable import SageKit

@Suite("Budget remaining shortcut")
struct GetBudgetRemainingIntentTests {
    /// Income of 0, as after onboarding with $0 or Delete All Data.
    @Test @MainActor
    func noIncomeMeansNoBudgetRatherThanOverBudget() throws {
        let (store, cleanUp) = try makeStore(income: 0)
        defer { cleanUp() }
        store.addExpense(Expense(name: "Groceries", amount: 80, category: .needs))
        store.addExpense(Expense(name: "Cinema", amount: 20, category: .wants))
        store.addExpense(Expense(name: "Transfer", amount: 50, category: .savings))
        try store.save()

        #expect(try store.budgetStatus(for: .needs) == .noBudget)
        #expect(try store.budgetStatus(for: .wants) == .noBudget)
        #expect(try store.budgetStatus(for: .savings) == .noTarget)
        #expect(try store.budgetStatus(for: nil) == .noBudget)
    }

    @Test @MainActor
    func zeroAllocationMeansNoBudgetForThatCategory() throws {
        let (store, cleanUp) = try makeStore(income: 1_000, allocation: (needs: 0.8, wants: 0, savings: 0.2))
        defer { cleanUp() }
        store.addExpense(Expense(name: "Cinema", amount: 20, category: .wants))
        try store.save()

        #expect(try store.budgetStatus(for: .wants) == .noBudget)
        #expect(try store.budgetStatus(for: .needs) == .underBudget(remaining: 800))
    }

    @Test @MainActor
    func statusComparesThisMonthsSpendingWithEachBudget() throws {
        // The default 50/30/20 split of 1,000 gives budgets of 500, 300 and 200.
        let (store, cleanUp) = try makeStore(income: 1_000)
        defer { cleanUp() }
        let month = try #require(Calendar.current.dateInterval(of: .month, for: .now))
        store.addExpense(Expense(name: "Groceries", amount: 80, category: .needs))
        store.addExpense(Expense(name: "Concert", amount: 350, category: .wants))
        store.addExpense(Expense(name: "Transfer", amount: 250, category: .savings))
        store.addExpense(Expense(name: "Last month", amount: 900, category: .needs, date: month.start.addingTimeInterval(-1)))
        try store.save()

        #expect(try store.budgetStatus(for: .needs) == .underBudget(remaining: 420))
        #expect(try store.budgetStatus(for: .wants) == .overBudget(by: 50))
        #expect(try store.budgetStatus(for: .savings) == .targetReached)
        #expect(try store.budgetStatus(for: nil) == .underBudget(remaining: 320))
    }

    @Test
    func categoryDialogs() {
        #expect(dialog(.noBudget, .needs) == "You haven't set a needs budget.")
        #expect(dialog(.noTarget, .savings) == "You haven't set a savings target.")
        #expect(dialog(.underBudget(remaining: 420), .needs)
                == "You have \(420.0.currencyString) remaining in your needs budget.")
        #expect(dialog(.overBudget(by: 50), .wants) == "You're \(50.0.currencyString) over your wants budget.")
        #expect(dialog(.belowTarget(remaining: 75), .savings)
                == "You're \(75.0.currencyString) away from your savings target this month.")
        #expect(dialog(.targetReached, .savings) == "You've reached your savings target this month.")
    }

    @Test
    func totalBudgetDialogs() {
        #expect(dialog(.noBudget, nil) == "You haven't set a monthly budget.")
        #expect(dialog(.underBudget(remaining: 320), nil)
                == "You have \(320.0.currencyString) left across all budgets this month.")
        #expect(dialog(.overBudget(by: 12.5), nil) == "You're \(12.5.currencyString) over your total budget this month.")
    }

    private func dialog(_ status: BudgetStatus, _ category: ExpenseCategory?) -> String {
        String(localized: GetBudgetRemainingIntent.dialog(for: status, category: category))
    }

    @MainActor
    private func makeStore(
        income: Int,
        allocation: (needs: Double, wants: Double, savings: Double)? = nil
    ) throws -> (ExpenseStore, cleanUp: () -> Void) {
        let suite = "GetBudgetRemainingIntentTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        preferences.set(income, forKey: "totalMonthlyIncome")
        if let allocation {
            preferences.set(allocation.needs, forKey: "needsPercent")
            preferences.set(allocation.wants, forKey: "wantsPercent")
            preferences.set(allocation.savings, forKey: "savingsPercent")
        }
        let store = ExpenseStore(modelContainer: try SageModelContainer.make(for: .test), preferences: preferences)
        return (store, { preferences.removePersistentDomain(forName: suite) })
    }
}
