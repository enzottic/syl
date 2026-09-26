import Foundation

/// How a month's spending compares with its budget.
///
/// Spending categories have a limit to stay under. Savings has a target to
/// reach, so going past it is a success rather than overspending. A budget of
/// zero or less means none is set, and is never reported as over budget.
///
/// The app, the iOS widgets and the Watch all use this, so they agree. It's
/// also compiled directly into the watch targets, so keep it Foundation-only.
@frozen
public enum BudgetStatus: Equatable, Sendable {
    /// No spending budget is set.
    case noBudget
    /// No savings target is set.
    case noTarget
    /// Spending is within the budget, with `remaining` still to spend.
    case underBudget(remaining: Double)
    /// Spending is over the budget by `amount`.
    case overBudget(by: Double)
    /// Savings is `remaining` short of its target.
    case belowTarget(remaining: Double)
    /// Savings has met or passed its target.
    case targetReached

    /// What the budget amount means for the money counted against it.
    @frozen
    public enum Goal: Equatable, Sendable {
        /// A limit that spending should stay under.
        case limit
        /// A target that savings should reach.
        case target
    }

    /// Differences smaller than this count as zero, so sums of cent amounts
    /// that land a hair past the budget don't read as over it.
    static let tolerance = 0.001

    public init(spent: Double, budget: Double, goal: Goal = .limit) {
        guard budget > 0 else {
            self = goal == .target ? .noTarget : .noBudget
            return
        }
        let difference = budget - spent
        switch goal {
        case .limit:
            self = difference < -Self.tolerance ? .overBudget(by: -difference) : .underBudget(remaining: max(difference, 0))
        case .target:
            self = difference > Self.tolerance ? .belowTarget(remaining: difference) : .targetReached
        }
    }

    /// Whether a budget or target is set.
    public var hasBudget: Bool {
        switch self {
        case .noBudget, .noTarget: false
        case .underBudget, .overBudget, .belowTarget, .targetReached: true
        }
    }

    /// Whether spending has gone past its limit. This is the only status to
    /// show as a warning.
    public var isOverBudget: Bool {
        if case .overBudget = self { return true }
        return false
    }
}
