//
//  WholeNumberCurrencyField.swift
//  FinanceTracker
//
//  Created by Enzo on 3/13/26.
//

import SwiftUI
import SageKit

struct WholeNumberCurrencyField: View {
    @Environment(AppConfiguration.self) private var config
    @Binding var amount: Int
    var isFocused: FocusState<Bool>.Binding
    @State private var rawValue = ""

    private var displayValue: String {
        amount.currencyString(code: config.ledgerCurrencyCode)
    }

    var body: some View {
        // Keep the native editor in the accessibility and keyboard focus systems.
        // Only the raw digits are transparent; the overlay formats the amount.
        TextField("", text: $rawValue)
            .font(.largeTitle.bold())
            .foregroundStyle(.clear)
            .tint(.clear)
            .keyboardType(.numberPad)
            .autocorrectionDisabled()
            .focused(isFocused)
            .frame(minHeight: 44)
            .overlay(alignment: .leading) {
                Text(displayValue)
                    .font(.largeTitle.bold())
                    .foregroundStyle(isFocused.wrappedValue ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityIdentifier("monthly-income-field")
            .accessibilityLabel("Monthly income")
            .accessibilityValue(displayValue)
            .accessibilityInputLabels(["Monthly income"])
            .onChange(of: rawValue) { _, text in
                // Model synchronization must not rewrite an existing income.
                guard Int(text) != amount else { return }
                // Update the editor as well as the model when normalizing digits
                // or enforcing the existing eight-digit whole-unit input limit.
                let digits = String(CentsFirstAmountInput.normalizedDigits(text).prefix(8))
                rawValue = digits
                amount = Int(digits) ?? 0
            }
            .onChange(of: amount, initial: true) { _, value in
                // A synced change (including zero) refreshes the editor without
                // applying the user-input limit to the stored income on appearance.
                if Int(rawValue) != value {
                    rawValue = value == 0 ? "" : String(value)
                }
            }
    }
}

#Preview {
    @Previewable @State var amount: Int = 0
    @Previewable @FocusState var isFocused: Bool

    VStack(spacing: 30) {
        WholeNumberCurrencyField(amount: $amount, isFocused: $isFocused)

        Text("Current amount: \(amount)")
            .foregroundStyle(.secondary)

        Button("Clear") {
            amount = 0
        }
    }
    .padding()
    .environment(AppConfiguration.preview)
}
