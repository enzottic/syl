import SwiftUI
import SageKit

struct ExpenseDetailRow: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.categoryColors) private var categoryColors

    let name: String
    let amount: Double
    let category: ExpenseCategory
    var nameLineLimit: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(category.color(in: categoryColors))
                    .baselineOffset(2)
                    .accessibilityHidden(true)
                Text(name)
                    .lineLimit(nameLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(amount.currencyString(code: config.ledgerCurrencyCode))
                .monospacedDigit().fixedSize()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityValue(category.rawValue)
    }
}
