import SwiftUI

struct ExpenseAmountPage: View {
    @Binding var amount: Double?
    @FocusState private var focusedField: Bool?

    var body: some View {
        VStack(spacing: 20) {
            Text("How much did you spend?")
                .font(.headline)
                .frame(maxWidth: .infinity)

            CentsFirstCurrencyField(
                amount: $amount,
                focus: $focusedField,
                focusValue: true,
                usesInlineKeypad: true
            )
        }
    }
}
