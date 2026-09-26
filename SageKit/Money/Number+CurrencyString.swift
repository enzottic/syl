//
//  Number+CurrencyString.swift
//  FinanceTracker
//
//  Created by Enzo on 10/1/25.
//
import Foundation

public extension Double {
    /// Pass an observed currency code from app views so currency changes refresh the display.
    func currencyString(code: String) -> String {
        formatted(.currency(code: code))
    }

    func currencyStringRounded(code: String) -> String {
        formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    /// The app-wide currency format. Uses the currency's own fraction digits
    /// (cents for USD/EUR, none for JPY), so amounts read the same on every screen.
    var currencyString: String {
        guard let code = LedgerCurrency.currentCode else {
            return "\(self.formatted()) (currency not confirmed)"
        }
        return currencyString(code: code)
    }
}

public extension Int {
    func currencyString(code: String) -> String {
        formatted(.currency(code: code).precision(.fractionLength(0)))
    }
}
