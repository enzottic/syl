import Foundation
import Testing
@testable import SageKit

struct CentsFirstAmountInputTests {
    @Test
    func usdTypingAndDeletionShiftMinorUnits() {
        var digits = ""
        for (key, expected) in [("1", 0.01), ("2", 0.12), ("3", 1.23), ("4", 12.34)] {
            digits = CentsFirstAmountInput.normalizedDigits(digits + key)
            #expect(CentsFirstAmountInput.amount(for: digits, currencyCode: "USD", isRefund: false) == expected)
        }
        let deletionAmounts: [Double?] = [1.23, 0.12, 0.01, nil]
        for expected in deletionAmounts {
            digits = CentsFirstAmountInput.normalizedDigits(String(digits.dropLast()))
            #expect(CentsFirstAmountInput.amount(for: digits, currencyCode: "USD", isRefund: false) == expected)
        }
        #expect(digits.isEmpty)
    }

    @Test
    func leadingZeroesStayEmptyButTrailingZeroesChangeMagnitude() {
        var digits = CentsFirstAmountInput.normalizedDigits("000")
        #expect(digits.isEmpty)
        #expect(CentsFirstAmountInput.amount(for: digits, currencyCode: "USD", isRefund: false) == nil)
        digits = CentsFirstAmountInput.normalizedDigits(digits + "5")
        for expected in [0.5, 5.0, 50.0] {
            digits = CentsFirstAmountInput.normalizedDigits(digits + "0")
            #expect(CentsFirstAmountInput.amount(for: digits, currencyCode: "USD", isRefund: false) == expected)
        }
        #expect(CentsFirstAmountInput.normalizedDigits("0005000") == digits)
    }

    @Test(arguments: [
        ("USD", "1", 0.01), ("USD", "1234", 12.34),
        ("JPY", "1", 1.0), ("JPY", "1234", 1234.0),
        ("KWD", "1", 0.001), ("KWD", "12345", 12.345), ("KWD", "48695", 48.695)
    ])
    func currencyPrecisionAndRefundsRoundTrip(currencyCode: String, digits: String, amount: Double) {
        #expect(CentsFirstAmountInput.digits(for: amount, currencyCode: currencyCode) == digits)
        #expect(CentsFirstAmountInput.digits(for: -amount, currencyCode: currencyCode) == digits)
        #expect(CentsFirstAmountInput.amount(for: digits, currencyCode: currencyCode, isRefund: false) == amount)
        #expect(CentsFirstAmountInput.amount(for: digits, currencyCode: currencyCode, isRefund: true) == -amount)
    }

    @Test(arguments: [
        ("USD", "100000000000", "99999999999", "100000000001", 999_999_999.99),
        ("JPY", "1000000000", "999999999", "1000000001", 999_999_999.0),
        ("KWD", "1000000000000", "999999999999", "1000000000001", 999_999_999.999)
    ])
    func inclusiveBillionLimitAndAdjacentMinorUnits(
        currencyCode: String, maximum: String, below: String, above: String, belowAmount: Double
    ) {
        for isRefund in [false, true] {
            let sign = isRefund ? -1.0 : 1.0
            #expect(CentsFirstAmountInput.amount(for: maximum, currencyCode: currencyCode, isRefund: isRefund) == sign * 1_000_000_000)
            #expect(CentsFirstAmountInput.amount(for: below, currencyCode: currencyCode, isRefund: isRefund) == sign * belowAmount)
            #expect(CentsFirstAmountInput.amount(for: above, currencyCode: currencyCode, isRefund: isRefund) == nil)
            #expect(CentsFirstAmountInput.digits(for: sign * 1_000_000_000, currencyCode: currencyCode) == maximum)
            #expect(CentsFirstAmountInput.digits(for: sign * belowAmount, currencyCode: currencyCode) == below)
            #expect(CentsFirstAmountInput.digits(for: sign * Double(1_000_000_000).nextUp, currencyCode: currencyCode).isEmpty)
        }
    }

    @Test(arguments: ["USD", "JPY", "KWD"])
    func invalidPrefillIsEmpty(currencyCode: String) {
        let invalid: [Double?] = [
            nil, 0, -0.0, .nan, .infinity, -.infinity,
            .leastNonzeroMagnitude, -.leastNonzeroMagnitude,
            .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
            1_000_000_001, -1_000_000_001
        ]
        for amount in invalid {
            #expect(CentsFirstAmountInput.digits(for: amount, currencyCode: currencyCode).isEmpty)
        }
    }

    @Test(arguments: [("USD", 12.345), ("JPY", 12.5), ("KWD", 12.3456)])
    func prefillRejectsExcessPrecisionRatherThanRounding(currencyCode: String, amount: Double) {
        #expect(CentsFirstAmountInput.digits(for: amount, currencyCode: currencyCode).isEmpty)
        #expect(CentsFirstAmountInput.digits(for: -amount, currencyCode: currencyCode).isEmpty)
    }

    @Test
    func prefillToleratesBinaryArithmeticNoise() {
        let amount = 0.1 + 0.2
        #expect(amount != 0.3)
        #expect(CentsFirstAmountInput.digits(for: amount, currencyCode: "USD") == "30")
        #expect(CentsFirstAmountInput.digits(for: -amount, currencyCode: "USD") == "30")
    }

    @Test(arguments: [12.0, -12.0, 12.34, -12.34])
    func currencySwitchRebuildsMinorUnitsWithoutRoundingHistory(amount: Double) {
        let usdDigits = CentsFirstAmountInput.digits(for: amount, currencyCode: "USD")
        let jpyDigits = CentsFirstAmountInput.digits(for: amount, currencyCode: "JPY")
        let kwdDigits = CentsFirstAmountInput.digits(for: amount, currencyCode: "KWD")

        #expect(usdDigits == (abs(amount) == 12 ? "1200" : "1234"))
        if abs(amount) == 12 {
            #expect(jpyDigits == "12")
            #expect(CentsFirstAmountInput.amount(for: jpyDigits, currencyCode: "JPY", isRefund: amount < 0) == amount)
        } else {
            // An incompatible historical amount has no editable register, not a rounded one.
            #expect(jpyDigits.isEmpty)
            #expect(CentsFirstAmountInput.amount(for: jpyDigits, currencyCode: "JPY", isRefund: amount < 0) == nil)
        }
        #expect(kwdDigits == (abs(amount) == 12 ? "12000" : "12340"))
        #expect(CentsFirstAmountInput.amount(for: kwdDigits, currencyCode: "KWD", isRefund: amount < 0) == amount)
        #expect(CentsFirstAmountInput.digits(for: amount, currencyCode: "USD") == usdDigits)
    }

    @Test(arguments: ["", "usd", "ZZZ", " USD "])
    func unsupportedCurrencyIsRejected(currencyCode: String) {
        #expect(CentsFirstAmountInput.digits(for: 12, currencyCode: currencyCode).isEmpty)
        #expect(CentsFirstAmountInput.amount(for: "1200", currencyCode: currencyCode, isRefund: false) == nil)
        #expect(CentsFirstAmountInput.amount(for: "1200", currencyCode: currencyCode, isRefund: true) == nil)
    }

    @Test(arguments: ["", "0", "000", "-1", "+1", "1.2", "1e2", " 12", "12x", "NaN", "inf"])
    func zeroAndNonDigitAmountsAreRejected(digits: String) {
        #expect(CentsFirstAmountInput.amount(for: digits, currencyCode: "USD", isRefund: false) == nil)
        #expect(CentsFirstAmountInput.amount(for: digits, currencyCode: "USD", isRefund: true) == nil)
    }

    @Test
    func unicodeDecimalDigitsNormalizeToASCII() {
        // Arabic-Indic, Persian, Devanagari, fullwidth, and mathematical decimal digits.
        let text = "\u{0660}\u{06F0}\u{0661}\u{06F2}\u{0969}\u{FF14}\u{1D7D3}"
        let digits = CentsFirstAmountInput.normalizedDigits(text)
        #expect(digits == "12345")
        #expect(CentsFirstAmountInput.amount(for: digits, currencyCode: "KWD", isRefund: false) == 12.345)
        #expect(CentsFirstAmountInput.normalizedDigits("0\u{0660}\u{06F0}\u{FF10}").isEmpty)
        #expect(CentsFirstAmountInput.normalizedDigits(" USD 00,120.30 ") == "12030")
        // Superscripts, circled numbers, and Roman numerals are not decimal digits.
        #expect(CentsFirstAmountInput.normalizedDigits("\u{00B2}\u{2462}\u{2163}abc").isEmpty)
    }

    @Test(arguments: ["100000000001", "18446744073709551616", String(repeating: "9", count: 10_000)])
    func oversizedInputIsNotTruncatedAndCannotOverflow(text: String) {
        let digits = CentsFirstAmountInput.normalizedDigits("000" + text)
        #expect(digits == text)
        #expect(CentsFirstAmountInput.amount(for: digits, currencyCode: "USD", isRefund: false) == nil)
        #expect(CentsFirstAmountInput.amount(for: digits, currencyCode: "USD", isRefund: true) == nil)
    }
}
