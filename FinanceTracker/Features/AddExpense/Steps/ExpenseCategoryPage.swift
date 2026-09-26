import SwiftUI
import SageKit

struct ExpenseCategoryPage: View {
    @Environment(\.categoryColors) private var categoryColors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var category: ExpenseCategory

    var body: some View {
        VStack(spacing: 20) {
            Text("Which category fits?")
                .font(.headline)
                .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                ForEach(ExpenseCategory.allCases, id: \.self) { option in
                    let isSelected = category == option
                    let color = option.color(in: categoryColors)

                    Button {
                        category = option
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(color)
                                .frame(width: 12, height: 12)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.rawValue)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(option.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? color : .secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(16)
                        .background(
                            isSelected ? color.opacity(0.18) : Color.cardBackground,
                            in: .rect(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isSelected ? color.opacity(0.6) : .clear, lineWidth: 1.5)
                        }
                        .contentShape(.rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("expense-category-\(option.rawValue.lowercased())")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: category)
            .sensoryFeedback(.selection, trigger: category)
        }
    }
}
