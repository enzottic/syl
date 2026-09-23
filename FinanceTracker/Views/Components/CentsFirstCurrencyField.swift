import SwiftUI
import SageKit

struct CentsFirstCurrencyField<Field: Hashable>: View {
    @Environment(AppConfiguration.self) private var config
    @Binding var amount: Double?
    var focus: FocusState<Field?>.Binding
    var focusValue: Field
    var accessibilityIdentifier: String = "expense-amount-field"
    var usesInlineKeypad = false

    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize = 48
    @State private var digits = ""
    @State private var isRefund = false
    @State private var selection: TextSelection?
    @State private var rejectedNonDigitInput = false

    private var currencyCode: String { config.ledgerCurrencyCode }
    private var fractionDigits: Int { LedgerCurrency.fractionDigits(for: currencyCode) }
    private var isFocused: Bool { focus.wrappedValue == focusValue }
    private var hasInvalidAmount: Bool {
        if let amount { return !MonetaryAmount.isValid(amount, currencyCode: currencyCode) }
        // Local digits can update before the parent amount binding catches up.
        // Only show an error when the register itself cannot form a valid amount.
        return !digits.isEmpty && CentsFirstAmountInput.amount(
            for: digits,
            currencyCode: currencyCode,
            isRefund: isRefund
        ) == nil
    }

    private var displayValue: String {
        if let amount {
            if !MonetaryAmount.isValid(amount, currencyCode: currencyCode) {
                return "\(amount.formatted(.number.precision(.fractionLength(0...16)))) \(currencyCode)"
            }
            return amount.currencyString(code: currencyCode)
        }
        let value = (Double(digits) ?? 0) / pow(10, Double(fractionDigits))
        return value.isFinite ? (value * (isRefund ? -1 : 1)).currencyString(code: currencyCode) : "Amount too large"
    }

    private var input: Binding<String> {
        Binding(get: { digits }, set: { text in
            guard text.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .decimalNumber }) else {
                rejectedNonDigitInput = true
                return
            }
            rejectedNonDigitInput = false
            digits = CentsFirstAmountInput.normalizedDigits(text)
            amount = CentsFirstAmountInput.amount(for: digits, currencyCode: currencyCode, isRefund: isRefund)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !usesInlineKeypad {
                HStack {
                    Text("Amount")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Menu {
                        Picker("Transaction type", selection: $isRefund) {
                            Text("Expense").tag(false)
                            Text("Refund").tag(true)
                        }
                        if amount != nil || !digits.isEmpty {
                            Button("Clear Amount", systemImage: "delete.left") {
                                digits = ""
                                amount = nil
                                rejectedNonDigitInput = false
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isRefund ? "Refund" : "Expense")
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline)
                        .foregroundStyle(isRefund ? .primary : .secondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("expense-amount-type")
                    .accessibilityLabel("Transaction type")
                    .accessibilityValue(isRefund ? "Refund" : "Expense")
                }
            }

            if usesInlineKeypad {
                Text(displayValue)
                    .font(.system(size: amountFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(amount == nil && digits.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier(accessibilityIdentifier)
                    .accessibilityLabel("Amount")
                    .accessibilityValue(displayValue)

                ExpenseAmountKeypad(digits: input)
            } else {
                // Keep the real input visible to accessibility and hit testing. Only its
                // raw digits are transparent; the localized amount supplies the display.
                TextField("", text: input, selection: $selection)
                    .font(.system(size: amountFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
                    .focused(focus, equals: focusValue)
                    .frame(minHeight: 60)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 8) {
                            Text(displayValue)
                                .font(.system(size: amountFontSize, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(amount == nil && digits.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.3)
                            if isFocused {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(.sageAccent)
                                    .frame(width: 2, height: 32)
                            }
                            Spacer(minLength: 0)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    .accessibilityIdentifier(accessibilityIdentifier)
                    .accessibilityLabel("Amount")
                    .accessibilityValue(displayValue)
                    .accessibilityHint(fractionDigits == 0 ? "Enter the amount using number keys" : "Enter digits; the decimal separator is added automatically")
            }

            if rejectedNonDigitInput || hasInvalidAmount {
                Text(rejectedNonDigitInput
                     ? "Use digits only. To enter a refund, choose Refund above."
                     : "To change this amount, clear and re-enter it. " + MonetaryAmount.validationMessage(currencyCode: currencyCode))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: selection) {
            // Minor-unit entry is a right-to-left register, not an editable decimal string.
            if let selection, case let .selection(range) = selection.indices,
               range != digits.endIndex..<digits.endIndex {
                self.selection = TextSelection(insertionPoint: digits.endIndex)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused { selection = TextSelection(insertionPoint: digits.endIndex) }
        }
        .onChange(of: amount, initial: true) { _, value in
            let current = CentsFirstAmountInput.amount(for: digits, currencyCode: currencyCode, isRefund: isRefund)
            guard current != value else { return }
            // History, receipt imports and edits must never round or rewrite the model.
            digits = CentsFirstAmountInput.digits(for: value, currencyCode: currencyCode)
            if let value { isRefund = value < 0 }
        }
        .onChange(of: currencyCode) {
            // Rebuild the register from the amount, never reinterpret old minor-unit digits.
            digits = CentsFirstAmountInput.digits(for: amount, currencyCode: currencyCode)
            selection = TextSelection(insertionPoint: digits.endIndex)
        }
        .onChange(of: isRefund) { _, refund in
            if let amount, (amount < 0) != refund {
                self.amount = refund ? -abs(amount) : abs(amount)
            }
        }
    }
}

#Preview {
    @Previewable @State var amount: Double? = nil
    @Previewable @FocusState var focus: Bool?
    CentsFirstCurrencyField(amount: $amount, focus: $focus, focusValue: true)
        .padding()
        .environment(AppConfiguration.preview)
}
