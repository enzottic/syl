import SwiftUI

struct BudgetSummaryRow: View {
    let title: LocalizedStringKey
    let amount: Double
    let currencyCode: String
    let color: Color
    let icon: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Label(title, systemImage: icon)
                Spacer(minLength: 12)
                Text(amount, format: .currency(code: currencyCode))
                    .fontWeight(.semibold)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                Text(amount, format: .currency(code: currencyCode))
                    .fontWeight(.semibold)
            }
        }
        .font(.body)
        .monospacedDigit()
        .textSelection(.enabled)
        .labelStyle(OnboardingCategoryLabelStyle(color: color))
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingCategoryLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: .rect(cornerRadius: 8))
            configuration.title
        }
    }
}
