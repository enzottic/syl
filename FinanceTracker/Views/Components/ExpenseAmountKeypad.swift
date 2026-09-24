import SwiftUI

struct ExpenseAmountKeypad: View {
    @Binding var digits: String

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(0..<3) { row in
                GridRow {
                    ForEach(1..<4) { column in
                        digitButton(row * 3 + column)
                    }
                }
            }
            GridRow {
                Button("Clear") {
                    digits = ""
                }
                .font(.callout.weight(.medium))
                .accessibilityLabel("Clear amount")

                digitButton(0)

                Button("Delete", systemImage: "delete.left") {
                    digits = String(digits.dropLast())
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Delete last digit")
            }
        }
        .buttonStyle(ExpenseAmountKeyStyle())
    }

    private func digitButton(_ digit: Int) -> some View {
        Button {
            digits.append(String(digit))
        } label: {
            Text(String(digit))
                .font(.title2.weight(.medium))
                .monospacedDigit()
        }
    }
}
