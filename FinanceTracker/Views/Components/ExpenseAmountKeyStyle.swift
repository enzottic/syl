import SwiftUI

struct ExpenseAmountKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.primary)
            .background(
                .primary.opacity(configuration.isPressed ? 0.12 : 0.04),
                in: .rect(cornerRadius: 16)
            )
            .contentShape(.rect(cornerRadius: 16))
    }
}
