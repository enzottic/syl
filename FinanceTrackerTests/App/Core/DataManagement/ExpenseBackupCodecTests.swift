import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Expense JSON backup codec")
struct ExpenseBackupCodecTests {
    @Test(arguments: ["nan", "inf", "1000000000.1", "-1000000000.1"])
    func invalidAmountIdentifiesTheRecord(amount: String) {
        let id = UUID().uuidString
        let row = ExpenseBackup.Record(id: id, name: "Problem expense", dateSecondsSince2001: 123,
                                       amount: amount, category: "Needs", note: "", tagIDs: [])
        do {
            try ExpenseBackupCodec.validate(.init(currency: "USD", tags: [], expenses: [row]))
            Issue.record("Expected invalid amount")
        } catch {
            #expect(error.localizedDescription.contains("Problem expense"))
            #expect(error.localizedDescription.contains(id))
            #expect(error.localizedDescription.contains(amount))
        }
    }

    @Test(arguments: ["short", "alpha", "nonfinite", "overflow"])
    @MainActor func rejectsInvalidTagColors(kind: String) throws {
        var appearance = try ExpenseBackup.Tag.Appearance(color: .red, emoji: "", symbolName: "tag")
        switch kind {
        case "short": appearance.light = [1, 0, 0]
        case "alpha": appearance.dark[3] = 2
        case "nonfinite": appearance.light[0] = .nan
        default: appearance.dark[0] = .greatestFiniteMagnitude
        }
        let id = UUID().uuidString
        let row = ExpenseBackup.Record(id: UUID().uuidString, name: "Test", dateSecondsSince2001: 123, amount: "5", category: "Needs", note: "", tagIDs: [id])
        let backup = ExpenseBackup(currency: "USD", tags: [.init(id: id, name: "Tag", appearance: appearance)], expenses: [row])
        #expect(throws: ExpenseBackupError.self) { try ExpenseBackupCodec.validate(backup) }
        #expect(throws: ExpenseBackupError.self) { try ExpenseBackupCodec.encode(backup) }
    }

    @Test
    func versionOneRemainsReadableAndVersionTwoRequiresRules() throws {
        let data = Data("{\"format\":\"sage.expense-backup\",\"version\":1,\"currency\":\"USD\",\"tags\":[],\"expenses\":[]}".utf8)
        #expect(try ExpenseBackupCodec.decode(data).recurringRules.isEmpty)
        let missingRules = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"version\":1", with: "\"version\":2").utf8)
        #expect(throws: (any Error).self) { try ExpenseBackupCodec.decode(missingRules) }
    }

    @Test(arguments: ["frequency", "zone", "amount", "date", "cursor", "duplicate", "tag", "missingCursor", "missingBoundary", "missingZone"])
    func rejectsInvalidRecurringRules(field: String) throws {
        let rule = ExpenseBackup.Rule(id: UUID().uuidString, name: "Rent", amount: "48.695", category: "Needs", note: "", tagIDs: [], frequency: "Monthly", startDateSecondsSince2001: 812_345_678)
        var backup = ExpenseBackup(currency: "USD", tags: [], expenses: [], recurringRules: [rule])
        if field.hasPrefix("missing") {
            var object = try #require(JSONSerialization.jsonObject(with: ExpenseBackupCodec.encode(backup)) as? [String: Any])
            var rules = try #require(object["recurringRules"] as? [[String: Any]])
            let key = field == "missingCursor" ? "lastGeneratedDateSecondsSince2001" : (field == "missingBoundary" ? "recurrenceEffectiveDateSecondsSince2001" : "recurrenceTimeZoneIdentifier")
            rules[0].removeValue(forKey: key)
            object["recurringRules"] = rules
            #expect(throws: (any Error).self) { try ExpenseBackupCodec.decode(JSONSerialization.data(withJSONObject: object)) }
            return
        }
        switch field {
        case "frequency": backup.recurringRules[0].frequency = "Hourly"
        case "zone": backup.recurringRules[0].recurrenceTimeZoneIdentifier = "Not/AZone"
        case "amount": backup.recurringRules[0].amount = "nan"
        case "date": backup.recurringRules[0].startDateSecondsSince2001 = .infinity
        case "cursor": backup.recurringRules[0].lastGeneratedDateSecondsSince2001 = Double.greatestFiniteMagnitude
        case "duplicate": backup.recurringRules.append(rule)
        default: backup.recurringRules[0].tagIDs = [UUID().uuidString]
        }
        #expect(throws: ExpenseBackupError.self) { try ExpenseBackupCodec.encode(backup) }
        #expect(throws: ExpenseBackupError.self) { try ExpenseBackupCodec.validate(backup) }
    }

    @Test(arguments: [0, 48.695, -48.695, 0.004, -0.004, Double.leastNonzeroMagnitude, MonetaryAmount.maximumMagnitude])
    func preciseRoundTrip(amount: Double) throws {
        let tagID = UUID().uuidString
        let otherTagID = UUID().uuidString
        let rule = UUID()
        let date = Date(timeIntervalSinceReferenceDate: 812_345_678.1234567)
        let row = ExpenseBackup.Record(id: UUID().uuidString, name: "A, \"quote\"\nline", dateSecondsSince2001: date.timeIntervalSinceReferenceDate,
                                       amount: String(amount), category: "Wants", note: "tab\t\r\n", tagIDs: [tagID, otherTagID],
                                       recurringExpenseID: rule.uuidString, recurringOccurrenceKey: RecurringExpenseOccurrence.key(ruleID: rule, scheduledDate: date.addingTimeInterval(-86_400)))
        let backup = ExpenseBackup(currency: "USD", tags: [.init(id: tagID, name: "Work|Travel"), .init(id: otherTagID, name: "Work|Travel")], expenses: [row])
        let data = try ExpenseBackupCodec.encode(backup)
        let restored = try ExpenseBackupCodec.decode(data)
        #expect(restored.expenses[0].date == date)
        #expect(Double(restored.expenses[0].amount) == amount)
        #expect(restored.expenses[0].name == row.name)
        #expect(restored.expenses[0].note == row.note)
        #expect(restored.expenses[0].recurringOccurrenceKey == row.recurringOccurrenceKey)
        #expect(restored.expenses[0].recurringExpenseID == rule.uuidString.lowercased())
        #expect(restored.tags.count == 2)
        #expect(restored.tags.allSatisfy { $0.name == "Work|Travel" && $0.id == $0.id.lowercased() })
        #expect(restored.tags.map(\.id) == restored.tags.map(\.id).sorted())
        #expect(try ExpenseBackupCodec.encode(restored) == data)
    }

    @Test
    func requiredNullableKeysAndUnknownFields() throws {
        #expect(throws: ExpenseBackupError.unsupportedVersion(3)) {
            try ExpenseBackupCodec.decode(Data("{\"format\":\"sage.expense-backup\",\"version\":3}".utf8))
        }
        let row = ExpenseBackup.Record(id: UUID().uuidString, name: "Legacy", dateSecondsSince2001: 123, amount: "1.23", category: "Needs", note: "", tagIDs: [], recurringExpenseID: UUID().uuidString)
        let backup = ExpenseBackup(currency: "USD", tags: [], expenses: [row])
        let data = try ExpenseBackupCodec.encode(backup)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var records = try #require(object["expenses"] as? [[String: Any]])
        #expect(records[0]["recurringOccurrenceKey"] is NSNull)
        object["future"] = ["ignored": true]
        records[0]["future"] = 2
        object["expenses"] = records
        let decoded = try ExpenseBackupCodec.decode(JSONSerialization.data(withJSONObject: object))
        #expect(decoded.expenses[0].recurringOccurrenceKey == nil)
        #expect(decoded.expenses[0].effectiveOccurrenceKey != nil)
        for key in ["id", "name", "dateSecondsSince2001", "amount", "category", "note", "tagIDs", "recurringExpenseID", "recurringOccurrenceKey"] {
            var missing = records
            missing[0].removeValue(forKey: key)
            object["expenses"] = missing
            let invalid = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) { try ExpenseBackupCodec.decode(invalid) }
        }
    }

    @Test(arguments: ["format", "version", "currency", "id", "duplicateExpense", "duplicateTag", "duplicateReference", "missingTag", "unusedTag", "category", "nan", "infinity", "amountOverflow", "dateOverflow", "dateNaN", "keyOnly", "wrongRule", "uppercaseKey", "noncanonicalMillis", "overflowMillis", "duplicateOccurrence"])
    func rejectsInvalidDTOAndExport(field: String) throws {
        let tag = ExpenseBackup.Tag(id: UUID().uuidString, name: "Tag")
        let rule = UUID()
        var row = ExpenseBackup.Record(id: UUID().uuidString, name: "Expense", dateSecondsSince2001: 123, amount: "3.456", category: "Needs", note: "", tagIDs: [tag.id], recurringExpenseID: rule.uuidString)
        row.recurringOccurrenceKey = row.effectiveOccurrenceKey
        var backup = ExpenseBackup(currency: "USD", tags: [tag], expenses: [row])
        switch field {
        case "format": backup.format = "other"
        case "version": backup.version = 3
        case "currency": backup.currency = "ZZZ"
        case "id": backup.expenses[0].id = "invalid"
        case "duplicateExpense": backup.expenses.append(row)
        case "duplicateTag": backup.tags.append(tag)
        case "duplicateReference": backup.expenses[0].tagIDs.append(tag.id)
        case "missingTag": backup.tags = []
        case "unusedTag": backup.expenses[0].tagIDs = []
        case "category": backup.expenses[0].category = "Unknown"
        case "nan": backup.expenses[0].amount = "nan"
        case "infinity": backup.expenses[0].amount = "inf"
        case "amountOverflow": backup.expenses[0].amount = "1000000000.1"
        case "dateOverflow": backup.expenses[0].dateSecondsSince2001 = Double(Int64.max)
        case "dateNaN": backup.expenses[0].dateSecondsSince2001 = .nan
        case "keyOnly": backup.expenses[0].recurringExpenseID = nil
        case "wrongRule": backup.expenses[0].recurringExpenseID = UUID().uuidString
        case "uppercaseKey": backup.expenses[0].recurringOccurrenceKey = row.recurringOccurrenceKey?.uppercased()
        case "noncanonicalMillis": backup.expenses[0].recurringOccurrenceKey = "v1:\(rule.uuidString.lowercased()):01"
        case "overflowMillis": backup.expenses[0].recurringOccurrenceKey = "v1:\(rule.uuidString.lowercased()):9223372036854775808"
        default:
            var duplicate = row
            duplicate.id = UUID().uuidString
            duplicate.recurringOccurrenceKey = nil
            backup.expenses.append(duplicate)
        }
        #expect(throws: ExpenseBackupError.self) { try ExpenseBackupCodec.validate(backup) }
        #expect(throws: ExpenseBackupError.self) { try ExpenseBackupCodec.encode(backup) }
    }

    @Test
    func safeMillisecondBoundary() {
        #expect(RecurringExpenseOccurrence.safeMilliseconds(Date(timeIntervalSince1970: Double(Int64.max) / 1_000)) == nil)
        #expect(RecurringExpenseOccurrence.safeMilliseconds(Date(timeIntervalSince1970: .infinity)) == nil)
        let rule = UUID()
        for time in [-1_723_500_000.123, 0, 1_723_500_000.123] {
            let date = Date(timeIntervalSince1970: time)
            #expect(RecurringExpenseOccurrence.safeKey(ruleID: rule, scheduledDate: date) == RecurringExpenseOccurrence.key(ruleID: rule, scheduledDate: date))
        }
    }

    @Test @MainActor
    func snapshotUsesPersistedModernOrLegacyNeverUnion() throws {
        let container = try SageModelContainer.make(for: .test)
        let ui = container.mainContext
        ui.autosaveEnabled = false
        let modern = ExpenseTag(name: "Modern|Tag", uiColor: .red, emoji: "", budget: 20)
        let legacy = ExpenseTag(name: "Legacy", uiColor: .blue, emoji: "")
        let unused = ExpenseTag(name: "Unused", uiColor: .gray, emoji: "")
        let first = Expense(name: "Modern", amount: 3.456, tags: [modern])
        first.tag = legacy
        let second = Expense(name: "Legacy", amount: 5)
        second.tag = legacy
        ui.insert(first)
        ui.insert(second)
        ui.insert(unused)
        try ui.save()
        first.name = "Pending"
        modern.name = "Pending tag"
        ui.insert(Expense(name: "Draft", amount: 1))
        let backup = try ExpenseBackupCodec.snapshot(modelContainer: container, currency: "USD")
        #expect(backup.expenses.count == 2)
        #expect(backup.expenses.first { $0.name == "Modern" }?.tagIDs == [modern.id.uuidString.lowercased()])
        #expect(backup.expenses.first { $0.name == "Legacy" }?.tagIDs == [legacy.id.uuidString.lowercased()])
        #expect(Set(backup.tags.map(\.name)) == ["Modern|Tag", "Legacy"])
        #expect(first.tag === legacy)
        #expect(first.name == "Pending")
        #expect(ui.hasChanges)
    }
}
