import SwiftUI

struct WatchBudgetBar: View {
    let total: Double
    let budget: Double
    let categories: [WatchCategorySnapshot]

    var body: some View {
        GeometryReader { geometry in
            let positiveTotal = categories.reduce(0) { $0 + max(0, $1.totalSpent) }
            let fraction = budget > 0 ? min(max(total / budget, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.22))
                HStack(spacing: 1) {
                    ForEach(categories.filter { $0.totalSpent > 0 }) { category in
                        Rectangle()
                            .fill(category.color.color)
                            .frame(width: max(0, geometry.size.width * fraction * category.totalSpent / max(positiveTotal, 1) - 1))
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

struct WatchBudgetRemaining: View {
    let spent: Double
    let budget: Double
    let currencyCode: String
    var isSavings = false

    var body: some View {
        switch BudgetStatus(spent: spent, budget: budget, goal: isSavings ? .target : .limit) {
        case .noBudget:
            Text("No budget set")
        case .noTarget:
            Text("No savings target")
        case .underBudget(let remaining):
            Text("\(remaining.formatted(.currency(code: currencyCode))) left")
        case .overBudget(let amount):
            Text("\(amount.formatted(.currency(code: currencyCode))) over budget")
        case .belowTarget(let remaining):
            Text("\(remaining.formatted(.currency(code: currencyCode))) to target")
        case .targetReached:
            Text("Target reached")
        }
    }
}
