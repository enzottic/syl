import Foundation
import SageKit

public nonisolated enum CentsFirstAmountInput {
    /// Display-only prefill. Callers must not write the result back to the model during synchronization.
    public static func digits(for amount: Double?, currencyCode: String) -> String {
        guard let amount, MonetaryAmount.isValid(amount, currencyCode: currencyCode) else { return "" }
        let scale = pow(10.0, Double(LedgerCurrency.fractionDigits(for: currencyCode)))
        guard let minorUnits = UInt64(exactly: (abs(amount) * scale).rounded()) else { return "" }
        return String(minorUnits)
    }

    /// Accepts ASCII minor-unit digits; normalize text separately before calling.
    public static func amount(for digits: String, currencyCode: String, isRefund: Bool) -> Double? {
        guard LedgerCurrency.validatedCode(currencyCode) != nil,
              !digits.isEmpty,
              digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let minorUnits = UInt64(digits), minorUnits > 0 else { return nil }

        let scale = pow(10.0, Double(LedgerCurrency.fractionDigits(for: currencyCode)))
        guard let maximumMinorUnits = UInt64(exactly: MonetaryAmount.maximumMagnitude * scale),
              minorUnits <= maximumMinorUnits else { return nil }
        let amount = Double(minorUnits) / scale * (isRefund ? -1 : 1)
        return MonetaryAmount.isValid(amount, currencyCode: currencyCode) ? amount : nil
    }

    public static func normalizedDigits(_ text: String) -> String {
        var digits = ""
        for scalar in text.unicodeScalars {
            guard scalar.properties.generalCategory == .decimalNumber,
                  let value = scalar.properties.numericValue else { continue }
            if value != 0 || !digits.isEmpty {
                digits.append(String(Int(value)))
            }
        }
        return digits
    }
}
