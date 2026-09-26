import Testing
@testable import SageKit

@Suite("Budget status")
struct BudgetStatusTests {
    @Test(arguments: [0.0, 12.5, 4_000.0])
    func zeroBudgetIsNoBudgetNotOverBudget(spent: Double) {
        let status = BudgetStatus(spent: spent, budget: 0)
        #expect(status == .noBudget)
        #expect(!status.hasBudget)
        #expect(!status.isOverBudget)
    }

    @Test(arguments: [0.0, 12.5, 4_000.0])
    func zeroSavingsTargetIsNoTargetNotOverBudget(saved: Double) {
        let status = BudgetStatus(spent: saved, budget: 0, goal: .target)
        #expect(status == .noTarget)
        #expect(!status.hasBudget)
        #expect(!status.isOverBudget)
    }

    @Test
    func negativeBudgetCountsAsNoBudget() {
        #expect(BudgetStatus(spent: 10, budget: -50) == .noBudget)
        #expect(BudgetStatus(spent: 10, budget: -50, goal: .target) == .noTarget)
    }

    /// Income of 0 (after onboarding or Delete All Data) gives every category a budget of 0.
    @Test
    func noCategoryIsOverBudgetWithoutIncome() {
        for category in ExpenseCategory.allCases {
            let status = BudgetStatus(spent: 250, budget: 0, goal: category.budgetGoal)
            #expect(!status.isOverBudget, "\(category.rawValue)")
            #expect(!status.hasBudget, "\(category.rawValue)")
        }
    }

    @Test
    func nothingSpentLeavesTheWholeBudget() {
        let status = BudgetStatus(spent: 0, budget: 500)
        #expect(status == .underBudget(remaining: 500))
        #expect(status.hasBudget)
        #expect(!status.isOverBudget)
    }

    @Test
    func nothingSavedIsTheWholeTargetToGo() {
        #expect(BudgetStatus(spent: 0, budget: 300, goal: .target) == .belowTarget(remaining: 300))
    }

    @Test
    func spendingPastTheBudgetIsOverBudget() {
        let status = BudgetStatus(spent: 625, budget: 500)
        #expect(status == .overBudget(by: 125))
        #expect(status.isOverBudget)
    }

    @Test
    func spendingExactlyTheBudgetIsNotOver() {
        let status = BudgetStatus(spent: 500, budget: 500)
        #expect(status == .underBudget(remaining: 0))
        #expect(!status.isOverBudget)
    }

    @Test
    func floatingPointSumsJustPastTheBudgetAreNotOver() {
        let spent = 0.1 + 0.2
        #expect(spent > 0.3)
        #expect(BudgetStatus(spent: spent, budget: 0.3) == .underBudget(remaining: 0))
        #expect(BudgetStatus(spent: 0.31, budget: 0.3).isOverBudget)
    }

    @Test
    func refundsLeaveMoreThanTheBudget() {
        #expect(BudgetStatus(spent: -40, budget: 500) == .underBudget(remaining: 540))
    }

    @Test(arguments: [300.0, 300.0004, 450.0])
    func savingsAtOrPastTargetIsReachedNotOverBudget(saved: Double) {
        let status = BudgetStatus(spent: saved, budget: 300, goal: .target)
        #expect(status == .targetReached)
        #expect(status.hasBudget)
        #expect(!status.isOverBudget)
    }

    @Test
    func savingsShortOfTargetIsBelowTarget() {
        let status = BudgetStatus(spent: 120, budget: 300, goal: .target)
        #expect(status == .belowTarget(remaining: 180))
        #expect(!status.isOverBudget)
    }

    @Test
    func onlySavingsHasATarget() {
        #expect(ExpenseCategory.savings.budgetGoal == .target)
        #expect(ExpenseCategory.needs.budgetGoal == .limit)
        #expect(ExpenseCategory.wants.budgetGoal == .limit)
    }
}
