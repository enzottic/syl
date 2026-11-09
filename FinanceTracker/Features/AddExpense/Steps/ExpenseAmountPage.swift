import SwiftUI

struct ExpenseAmountPage: View {
    @Binding var amount: Double?
    var onSubmit: () -> Void
    @FocusState private var focusedField: Bool?

    var body: some View {
        VStack(spacing: 20) {
            Text("Amount")
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            CentsFirstCurrencyField(
                amount: $amount,
                focus: $focusedField,
                focusValue: true,
                usesInlineKeypad: true
            )
        }
        .background {
            Button("Next", action: onSubmit)
                .keyboardShortcut(.return, modifiers: [])
                .hidden()
                .accessibilityHidden(true)
        }
    }
}
