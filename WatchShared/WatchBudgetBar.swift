import SwiftUI

struct WatchBudgetBar: View {
    let total: Double
    let budget: Double
    let categories: [WatchCategorySnapshot]
    /// Fraction of the month elapsed; draws a marker showing where spending would be on an even pace.
    var pace: Double? = nil

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
                if let pace {
                    Capsule()
                        .fill(.primary)
                        .frame(width: 2, height: geometry.size.height + 6)
                        .offset(x: geometry.size.width * min(max(pace, 0), 1) - 1)
                }
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

    private var status: BudgetStatus {
        BudgetStatus(spent: spent, budget: budget, goal: isSavings ? .target : .limit)
    }

    var body: some View {
        text.foregroundStyle(color)
    }

    private var text: Text {
        let format = FloatingPointFormatStyle<Double>.Currency(code: currencyCode).precision(.fractionLength(0))
        switch status {
        case .noBudget:
            return Text("No budget set")
        case .noTarget:
            return Text("No savings target")
        case .underBudget(let remaining):
            return Text("\(remaining.formatted(format)) left")
        case .overBudget(let amount):
            return Text("\(amount.formatted(format)) over")
        case .belowTarget(let remaining):
            return Text("\(remaining.formatted(format)) to go")
        case .targetReached:
            return Text("Target reached")
        }
    }

    private var color: Color {
        switch status {
        case .underBudget: .green
        case .overBudget: .red
        case .targetReached: .green
        case .noBudget, .noTarget, .belowTarget: .primary
        }
    }
}
