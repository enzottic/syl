//
//  ExpenseCSVCodec.swift
//  SageKit
//

import Foundation
import SageKit

public nonisolated struct ExportableExpense: Sendable, Equatable {
    public let name: String
    public let date: Date
    public let amount: Double
    public let category: String
    /// Pipe-joined tag names. This keeps the CSV format compatible with older Sage exports.
    public let tag: String
    public let note: String
    /// Nil only for rows from legacy six-column exports or newly prepared export data.
    public let currencyCode: String?

    public var tagNames: [String] {
        tag.split(separator: "|").map(String.init)
    }

    public init(name: String, date: Date, amount: Double, category: String, tag: String, note: String, currencyCode: String? = nil) {
        self.name = name
        self.date = date
        self.amount = amount
        self.category = category
        self.tag = tag
        self.note = note
        self.currencyCode = currencyCode
    }
}

public nonisolated enum ExpenseCSVError: LocalizedError, Equatable {
    case invalidHeader(expected: [String], actual: [String])
    case malformedCSV(row: Int, reason: String)
    case invalidColumnCount(row: Int, expected: Int, actual: Int)
    case invalidDate(row: Int, value: String)
    case invalidAmount(row: Int, value: String)
    case invalidCategory(row: Int, value: String)
    case invalidCurrency(String)
    case mixedCurrencies
    case currencyMismatch(expected: String, actual: String)
    case legacyCurrencyConfirmationRequired

    public var errorDescription: String? {
        switch self {
        case .invalidHeader(let expected, let actual):
            return "Invalid CSV header. Expected \(expected.joined(separator: ",")); found \(actual.joined(separator: ","))."
        case .malformedCSV(let row, let reason):
            return "Row \(row): \(reason)"
        case .invalidColumnCount(let row, let expected, let actual):
            return "Row \(row): expected \(expected) columns; found \(actual)."
        case .invalidDate(let row, let value):
            return "Row \(row): invalid date '\(value)'."
        case .invalidAmount(let row, let value):
            return "Row \(row): invalid amount '\(value)'. Use a finite, nonzero amount (negative for refunds), no more than 1 billion in magnitude. CSV backups preserve amounts without rounding."
        case .invalidCategory(let row, let value):
            return "Row \(row): invalid category '\(value)'."
        case .invalidCurrency(let code):
            return "Invalid CSV currency '\(code)'. Choose a file with a supported ISO currency code."
        case .mixedCurrencies:
            return "This CSV contains mixed currencies. Syl imports only one ledger currency and does not convert amounts."
        case .currencyMismatch(let expected, let actual):
            return "This CSV uses \(actual), but your ledger uses \(expected). No expenses were imported. Syl does not convert currencies."
        case .legacyCurrencyConfirmationRequired:
            return "This CSV has no currency information. Confirm the currency of its amounts before importing."
        }
    }
}

public nonisolated enum ExpenseCSVCodec {
    public static let legacyHeader = ["name", "date", "amount", "category", "tag", "note"]
    public static let header = legacyHeader + ["currency"]

    public static func encode(_ expenses: [ExportableExpense], currencyCode: String) throws -> String {
        try validateCurrency(expenses, ledgerCurrencyCode: currencyCode, allowLegacy: true)
        let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let rows = expenses.map { expense in
            [
                expense.name,
                expense.date.formatted(dateStyle),
                String(expense.amount),
                expense.category,
                expense.tag,
                expense.note,
                currencyCode
            ]
            .map(encodeField)
            .joined(separator: ",")
        }

        return ([header.joined(separator: ",")] + rows).joined(separator: "\r\n")
    }

    public static func decode(_ csv: String) throws -> [ExportableExpense] {
        let records = try parseRecords(csv)
        guard let headerRecord = records.first else {
            throw ExpenseCSVError.invalidHeader(expected: header, actual: [])
        }

        var actualHeader = headerRecord.fields
        if let first = actualHeader.first {
            actualHeader[0] = String(first.trimmingPrefix("\u{FEFF}"))
        }
        guard actualHeader == header || actualHeader == legacyHeader else {
            throw ExpenseCSVError.invalidHeader(expected: header, actual: actualHeader)
        }

        var expenses: [ExportableExpense] = []
        var fileCurrency: String?
        expenses.reserveCapacity(max(0, records.count - 1))

        for record in records.dropFirst() {
            guard record.fields.count == actualHeader.count else {
                throw ExpenseCSVError.invalidColumnCount(
                    row: record.row,
                    expected: actualHeader.count,
                    actual: record.fields.count
                )
            }

            let fields = record.fields
            guard let date = parseDate(fields[1]) else {
                throw ExpenseCSVError.invalidDate(row: record.row, value: fields[1])
            }
            guard let amount = Double(fields[2]), isValidBackupAmount(amount) else {
                throw ExpenseCSVError.invalidAmount(row: record.row, value: fields[2])
            }
            guard ExpenseCategory(rawValue: fields[3]) != nil else {
                throw ExpenseCSVError.invalidCategory(row: record.row, value: fields[3])
            }
            var currencyCode: String?
            if actualHeader == header {
                guard let code = LedgerCurrency.validatedCode(fields[6]) else {
                    throw ExpenseCSVError.invalidCurrency(fields[6])
                }
                if let fileCurrency, fileCurrency != code {
                    throw ExpenseCSVError.mixedCurrencies
                }
                fileCurrency = code
                currencyCode = code
            }
            expenses.append(
                ExportableExpense(
                    name: fields[0],
                    date: date,
                    amount: amount,
                    category: fields[3],
                    tag: fields[4],
                    note: fields[5],
                    currencyCode: currencyCode
                )
            )
        }

        return expenses
    }

    /// Validate the complete batch before insertion. Legacy rows need currency consent.
    public static func validateCurrency(
        _ expenses: [ExportableExpense],
        ledgerCurrencyCode: String,
        allowLegacy: Bool = false
    ) throws {
        guard LedgerCurrency.validatedCode(ledgerCurrencyCode) != nil else {
            throw ExpenseCSVError.invalidCurrency(ledgerCurrencyCode)
        }
        let codes = Set(expenses.compactMap(\.currencyCode))
        for code in codes where LedgerCurrency.validatedCode(code) == nil {
            throw ExpenseCSVError.invalidCurrency(code)
        }
        let hasLegacy = expenses.contains { $0.currencyCode == nil }
        guard codes.count <= 1, !(hasLegacy && !codes.isEmpty) else {
            throw ExpenseCSVError.mixedCurrencies
        }
        if let code = codes.first, code != ledgerCurrencyCode {
            throw ExpenseCSVError.currencyMismatch(expected: ledgerCurrencyCode, actual: code)
        }
        if hasLegacy && !allowLegacy {
            throw ExpenseCSVError.legacyCurrencyConfirmationRequired
        }
        for (index, expense) in expenses.enumerated() {
            guard RecurringExpenseOccurrence.safeMilliseconds(expense.date) != nil else {
                throw ExpenseCSVError.invalidDate(row: index + 2, value: String(expense.date.timeIntervalSinceReferenceDate))
            }
            guard ExpenseCategory(rawValue: expense.category) != nil else {
                throw ExpenseCSVError.invalidCategory(row: index + 2, value: expense.category)
            }
            guard isValidBackupAmount(expense.amount) else {
                throw ExpenseCSVError.invalidAmount(row: index + 2, value: String(expense.amount))
            }
        }
    }

    private static func isValidBackupAmount(_ amount: Double) -> Bool {
        // Saved expenses can predate minor-unit validation. Backups must round-trip
        // their precision without applying today's entry rules or changing amounts.
        amount.isFinite && amount != 0 && abs(amount) <= MonetaryAmount.maximumMagnitude
    }

    private static func encodeField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? fractionalStyle.parseStrategy.parse(value) {
            return date
        }
        if let date = try? Date(value, strategy: .iso8601) {
            return date
        }

        // Support files made by Sage before ISO 8601 export was added.
        let legacyFormatter = DateFormatter()
        legacyFormatter.locale = Locale(identifier: "en_US_POSIX")
        legacyFormatter.calendar = Calendar(identifier: .gregorian)
        legacyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        legacyFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return legacyFormatter.date(from: value)
    }

    private struct CSVRecord {
        let fields: [String]
        let row: Int
    }

    private static func parseRecords(_ csv: String) throws -> [CSVRecord] {
        let scalars = Array(csv.unicodeScalars)
        var records: [CSVRecord] = []
        var fields: [String] = []
        var field = ""
        var index = 0
        var physicalRow = 1
        var recordRow = 1
        var recordStarted = false
        var isQuoted = false
        var closedQuote = false

        func isNewline(_ scalar: Unicode.Scalar) -> Bool {
            scalar == "\n" || scalar == "\r"
        }

        func newlineLength(at position: Int) -> Int {
            if scalars[position] == "\r", position + 1 < scalars.count, scalars[position + 1] == "\n" {
                return 2
            }
            return 1
        }

        func appendRecord() {
            fields.append(field)
            records.append(CSVRecord(fields: fields, row: recordRow))
            fields.removeAll(keepingCapacity: true)
            field.removeAll(keepingCapacity: true)
            recordStarted = false
            closedQuote = false
        }

        while index < scalars.count {
            let scalar = scalars[index]

            if isQuoted {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.unicodeScalars.append(scalar)
                        index += 2
                    } else {
                        isQuoted = false
                        closedQuote = true
                        index += 1
                    }
                } else if isNewline(scalar) {
                    let length = newlineLength(at: index)
                    field.unicodeScalars.append(scalar)
                    if length == 2 {
                        field.unicodeScalars.append(scalars[index + 1])
                    }
                    physicalRow += 1
                    index += length
                } else {
                    field.unicodeScalars.append(scalar)
                    index += 1
                }
                continue
            }

            if closedQuote {
                if scalar == "," {
                    fields.append(field)
                    field.removeAll(keepingCapacity: true)
                    closedQuote = false
                    recordStarted = true
                    index += 1
                } else if isNewline(scalar) {
                    let length = newlineLength(at: index)
                    appendRecord()
                    physicalRow += 1
                    recordRow = physicalRow
                    index += length
                } else {
                    throw ExpenseCSVError.malformedCSV(
                        row: recordRow,
                        reason: "unexpected character after a closing quote."
                    )
                }
                continue
            }

            if scalar == "\"" {
                guard field.isEmpty else {
                    throw ExpenseCSVError.malformedCSV(
                        row: recordRow,
                        reason: "a quote must be at the start of a field."
                    )
                }
                isQuoted = true
                recordStarted = true
                index += 1
            } else if scalar == "," {
                fields.append(field)
                field.removeAll(keepingCapacity: true)
                recordStarted = true
                index += 1
            } else if isNewline(scalar) {
                let length = newlineLength(at: index)
                appendRecord()
                physicalRow += 1
                recordRow = physicalRow
                index += length
            } else {
                field.unicodeScalars.append(scalar)
                recordStarted = true
                index += 1
            }
        }

        if isQuoted {
            throw ExpenseCSVError.malformedCSV(row: recordRow, reason: "quoted field is not closed.")
        }
        if closedQuote || recordStarted || !fields.isEmpty || !field.isEmpty {
            appendRecord()
        }

        return records
    }
}
