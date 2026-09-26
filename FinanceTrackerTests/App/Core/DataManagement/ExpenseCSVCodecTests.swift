import Foundation
import Testing
@testable import SageKit

@Suite("Expense CSV codec")
struct ExpenseCSVCodecTests {
    @Test
    func exportThenImportPreservesSpecialCharactersAndEmptyFields() throws {
        let source = ExportableExpense(
            name: "Coffee, \"large\"",
            date: Date(timeIntervalSince1970: 1_723_500_000.125),
            amount: 12.34,
            category: ExpenseCategory.wants.rawValue,
            tag: "",
            note: "First line\nSecond \"quoted\" line"
        )

        let decoded = try ExpenseCSVCodec.decode(ExpenseCSVCodec.encode([source], currencyCode: "EUR"))

        #expect(decoded.count == 1)
        let expense = try #require(decoded.first)
        #expect(expense.name == source.name)
        #expect(abs(expense.date.timeIntervalSince1970 - source.date.timeIntervalSince1970) < 0.000_001)
        #expect(expense.amount == source.amount)
        #expect(expense.category == source.category)
        #expect(expense.tag == source.tag)
        #expect(expense.note == source.note)
        #expect(expense.currencyCode == "EUR")
    }

    @Test
    func decodeSupportsQuotedFieldsAndEmbeddedLineBreaks() throws {
        let csv = """
        name,date,amount,category,tag,note
        "Dinner, with friends",2026-08-12T18:30:00Z,42.5,Wants,Dining,"She said ""hello"".
        Then we left."
        """

        let decoded = try ExpenseCSVCodec.decode(csv)

        #expect(decoded.count == 1)
        let expense = try #require(decoded.first)
        #expect(expense.name == "Dinner, with friends")
        #expect(expense.note == "She said \"hello\".\nThen we left.")
        #expect(expense.currencyCode == nil)
    }

    @Test
    func legacyImportRequiresExplicitCurrencyConsent() throws {
        let csv = "name,date,amount,category,tag,note\nCoffee,2026-08-12T18:30:00Z,4.5,Wants,Food,"
        let expenses = try ExpenseCSVCodec.decode(csv)
        #expect(throws: ExpenseCSVError.legacyCurrencyConfirmationRequired) {
            try ExpenseCSVCodec.validateCurrency(expenses, ledgerCurrencyCode: "USD")
        }
        try ExpenseCSVCodec.validateCurrency(expenses, ledgerCurrencyCode: "USD", allowLegacy: true)
        #expect(expenses.first?.amount == 4.5)
        #expect(expenses.first?.currencyCode == nil)
    }

    @Test
    func importAndExportRejectCurrencyMismatchWithoutConversion() throws {
        let csv = "name,date,amount,category,tag,note,currency\nCoffee,2026-08-12T18:30:00Z,4.5,Wants,Food,,EUR"
        let expenses = try ExpenseCSVCodec.decode(csv)
        try ExpenseCSVCodec.validateCurrency(expenses, ledgerCurrencyCode: "EUR")
        #expect(throws: ExpenseCSVError.currencyMismatch(expected: "USD", actual: "EUR")) {
            try ExpenseCSVCodec.validateCurrency(expenses, ledgerCurrencyCode: "USD", allowLegacy: true)
        }
        #expect(throws: ExpenseCSVError.currencyMismatch(expected: "USD", actual: "EUR")) {
            try ExpenseCSVCodec.encode(expenses, currencyCode: "USD")
        }
        #expect(expenses.first?.amount == 4.5)
    }

    @Test
    func decodeRejectsMixedCurrenciesAsOneBatch() {
        let csv = """
        name,date,amount,category,tag,note,currency
        Coffee,2026-08-12T18:30:00Z,4.5,Wants,Food,,EUR
        Rent,2026-08-01T12:00:00Z,1000,Needs,Housing,,USD
        """
        #expect(throws: ExpenseCSVError.mixedCurrencies) {
            try ExpenseCSVCodec.decode(csv)
        }
    }

    @Test(arguments: ["", "usd", "ZZZ", " US "])
    func currencyColumnMustContainAValidCode(code: String) {
        let csv = "name,date,amount,category,tag,note,currency\nCoffee,2026-08-12T18:30:00Z,4.5,Wants,Food,,\(code)"
        #expect(throws: ExpenseCSVError.invalidCurrency(code)) {
            try ExpenseCSVCodec.decode(csv)
        }
    }

    @Test
    func validationDoesNotTreatMixedLegacyAndDenominatedRowsAsConsent() {
        let expenses = [nil, "EUR"].map { code in
            ExportableExpense(name: "Coffee", date: .now, amount: 4.5, category: "Wants", tag: "", note: "", currencyCode: code)
        }
        #expect(throws: ExpenseCSVError.mixedCurrencies) {
            try ExpenseCSVCodec.validateCurrency(expenses, ledgerCurrencyCode: "EUR", allowLegacy: true)
        }
    }

    @Test
    func emptyExportHasCurrencyHeaderButDoesNotInferCurrencyOnImport() throws {
        let csv = try ExpenseCSVCodec.encode([], currencyCode: "EUR")
        #expect(csv == "name,date,amount,category,tag,note,currency")
        #expect(try ExpenseCSVCodec.decode(csv).isEmpty)
        #expect(throws: ExpenseCSVError.invalidCurrency("ZZZ")) {
            try ExpenseCSVCodec.encode([], currencyCode: "ZZZ")
        }
    }

    @Test
    func decodeRejectsInvalidHeader() {
        #expect(
            throws: ExpenseCSVError.invalidHeader(
                expected: ExpenseCSVCodec.header,
                actual: ["title", "date", "amount", "category", "tag", "note"]
            )
        ) {
            try ExpenseCSVCodec.decode("title,date,amount,category,tag,note")
        }
    }

    @Test
    func decodeReportsInvalidValuesWithoutPartialData() {
        let csv = """
        name,date,amount,category,tag,note
        Coffee,2026-08-12T18:30:00Z,4.5,Wants,Food,
        Rent,2026-08-01T12:00:00Z,not-a-number,Needs,Housing,
        """

        #expect(throws: ExpenseCSVError.invalidAmount(row: 3, value: "not-a-number")) {
            try ExpenseCSVCodec.decode(csv)
        }
    }

    @Test
    func decodeRejectsUnclosedQuotedField() {
        let csv = "name,date,amount,category,tag,note\nCoffee,2026-08-12T18:30:00Z,4.5,Wants,Food,\"not closed"

        #expect(
            throws: ExpenseCSVError.malformedCSV(row: 2, reason: "quoted field is not closed.")
        ) {
            try ExpenseCSVCodec.decode(csv)
        }
    }

    @Test(arguments: [
        ("USD", "48.695"), ("USD", "-48.695"),
        ("USD", "0.004"), ("USD", "-12.345"), ("USD", "999999999.990001"),
        ("JPY", "4.5"), ("KWD", "12.3456")
    ])
    func backupRoundTripsHistoricalPrecision(currencyCode: String, amount: String) throws {
        let csv = """
        name,date,amount,category,tag,note,currency
        Coffee,2026-08-12T18:30:00Z,4,Wants,,"Two
        lines",\(currencyCode)
        Historical,2026-08-12T18:30:00Z,\(amount),Wants,,,\(currencyCode)
        """
        let expenses = try ExpenseCSVCodec.decode(csv)
        try ExpenseCSVCodec.validateCurrency(expenses, ledgerCurrencyCode: currencyCode)
        let encoded = try ExpenseCSVCodec.encode(expenses, currencyCode: currencyCode)
        let decoded = try ExpenseCSVCodec.decode(encoded)
        #expect(decoded.count == 2)
        #expect(decoded.last?.amount == Double(amount))
        #expect(decoded.last?.currencyCode == currencyCode)
        #expect(decoded.first?.note == "Two\nlines")
    }

    @Test
    func decodeReportsPhysicalRowAfterMultilineField() {
        let csv = """
        name,date,amount,category,tag,note,currency
        Coffee,2026-08-12T18:30:00Z,4,Wants,,"Two
        lines",USD
        Invalid,2026-08-12T18:30:00Z,NaN,Wants,,,USD
        """
        #expect(throws: ExpenseCSVError.invalidAmount(row: 4, value: "NaN")) {
            try ExpenseCSVCodec.decode(csv)
        }
    }

    @Test(arguments: ["0", "-0", "NaN", "inf", "-inf", "1000000001", "-1000000001"])
    func decodeRejectsInvalidAmountsEvenWithoutCurrency(amount: String) {
        for currencySuffix in ["", ",USD"] {
            let header = currencySuffix.isEmpty ? ExpenseCSVCodec.legacyHeader : ExpenseCSVCodec.header
            let csv = header.joined(separator: ",")
                + "\nInvalid,2026-08-12T18:30:00Z,\(amount),Wants,,\(currencySuffix)"
            #expect(throws: ExpenseCSVError.invalidAmount(row: 2, value: amount)) {
                try ExpenseCSVCodec.decode(csv)
            }
        }
    }

    @Test(arguments: [("USD", -12.34), ("JPY", -123.0), ("KWD", -12.345), ("KWD", -0.001)])
    func legacyRefundRoundTripsWithoutConversion(currencyCode: String, amount: Double) throws {
        let csv = "name,date,amount,category,tag,note\nRefund,2026-08-12T18:30:00Z,\(amount),Wants,,"
        let expenses = try ExpenseCSVCodec.decode(csv)
        try ExpenseCSVCodec.validateCurrency(expenses, ledgerCurrencyCode: currencyCode, allowLegacy: true)
        let encoded = try ExpenseCSVCodec.encode(expenses, currencyCode: currencyCode)
        let decoded = try ExpenseCSVCodec.decode(encoded)
        #expect(decoded.first?.amount == amount)
        #expect(decoded.first?.currencyCode == currencyCode)
    }

    @Test
    func legacyConsentPreservesHistoricalPrecision() throws {
        let csv = "name,date,amount,category,tag,note\nCoffee,2026-08-12T18:30:00Z,4.5,Wants,,"
        let expenses = try ExpenseCSVCodec.decode(csv)
        #expect(throws: ExpenseCSVError.legacyCurrencyConfirmationRequired) {
            try ExpenseCSVCodec.validateCurrency(expenses, ledgerCurrencyCode: "JPY")
        }
        try ExpenseCSVCodec.validateCurrency(expenses, ledgerCurrencyCode: "JPY", allowLegacy: true)
        let decoded = try ExpenseCSVCodec.decode(ExpenseCSVCodec.encode(expenses, currencyCode: "JPY"))
        #expect(decoded.first?.amount == 4.5)
        #expect(decoded.first?.currencyCode == "JPY")
    }

    @Test(arguments: [0.0, -0.0, 1_000_000_001, -1_000_000_001, Double.nan, Double.infinity, -Double.infinity])
    func validationAndExportRejectInvalidSavedAmounts(amount: Double) {
        let expenses = [
            ExportableExpense(name: "Valid", date: .now, amount: 1, category: "Wants", tag: "", note: ""),
            ExportableExpense(name: "Invalid", date: .now, amount: amount, category: "Wants", tag: "", note: "")
        ]
        let expected = ExpenseCSVError.invalidAmount(row: 3, value: String(amount))
        #expect(throws: expected) {
            try ExpenseCSVCodec.validateCurrency(expenses, ledgerCurrencyCode: "USD", allowLegacy: true)
        }
        #expect(throws: expected) {
            try ExpenseCSVCodec.encode(expenses, currencyCode: "USD")
        }
    }

    @Test
    func binaryArithmeticRoundTripsWithoutRounding() throws {
        let amount = 0.1 + 0.2
        let expenses = [ExportableExpense(name: "Sum", date: .now, amount: amount, category: "Wants", tag: "", note: "")]
        let decoded = try ExpenseCSVCodec.decode(ExpenseCSVCodec.encode(expenses, currencyCode: "USD"))
        #expect(decoded.first?.amount == amount)
    }
}
