import Foundation
import SageKit
import SwiftData
import UIKit

public nonisolated struct ExpenseBackup: Codable, Equatable, Sendable {
    public var format: String
    public var version: Int
    public var currency: String
    public var tags: [Tag]
    public var expenses: [Record]
    public var recurringRules: [Rule]

    public init(currency: String, tags: [Tag], expenses: [Record], recurringRules: [Rule] = [], format: String = "sage.expense-backup", version: Int = 2) {
        self.format = format
        self.version = version
        self.currency = currency
        self.tags = tags
        self.expenses = expenses
        self.recurringRules = recurringRules
    }

    private enum CodingKeys: String, CodingKey { case format, version, currency, tags, expenses, recurringRules }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        format = try values.decode(String.self, forKey: .format)
        version = try values.decode(Int.self, forKey: .version)
        currency = try values.decode(String.self, forKey: .currency)
        tags = try values.decode([Tag].self, forKey: .tags)
        expenses = try values.decode([Record].self, forKey: .expenses)
        recurringRules = version == 1 ? [] : try values.decode([Rule].self, forKey: .recurringRules)
    }

    public struct Rule: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var amount: String
        public var category: String
        public var note: String
        public var tagIDs: [String]
        public var frequency: String
        public var startDateSecondsSince2001: Double
        public var endDateSecondsSince2001: Double?
        public var lastGeneratedDateSecondsSince2001: Double?
        public var recurrenceTimeZoneIdentifier: String?
        public var recurrenceEffectiveDateSecondsSince2001: Double?

        public init(id: String, name: String, amount: String, category: String, note: String, tagIDs: [String],
                    frequency: String, startDateSecondsSince2001: Double, endDateSecondsSince2001: Double? = nil,
                    lastGeneratedDateSecondsSince2001: Double? = nil, recurrenceTimeZoneIdentifier: String? = nil,
                    recurrenceEffectiveDateSecondsSince2001: Double? = nil) {
            self.id = id
            self.name = name
            self.amount = amount
            self.category = category
            self.note = note
            self.tagIDs = tagIDs
            self.frequency = frequency
            self.startDateSecondsSince2001 = startDateSecondsSince2001
            self.endDateSecondsSince2001 = endDateSecondsSince2001
            self.lastGeneratedDateSecondsSince2001 = lastGeneratedDateSecondsSince2001
            self.recurrenceTimeZoneIdentifier = recurrenceTimeZoneIdentifier
            self.recurrenceEffectiveDateSecondsSince2001 = recurrenceEffectiveDateSecondsSince2001
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, amount, category, note, tagIDs, frequency, startDateSecondsSince2001,
                 endDateSecondsSince2001, lastGeneratedDateSecondsSince2001, recurrenceTimeZoneIdentifier,
                 recurrenceEffectiveDateSecondsSince2001
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            name = try values.decode(String.self, forKey: .name)
            amount = try values.decode(String.self, forKey: .amount)
            category = try values.decode(String.self, forKey: .category)
            note = try values.decode(String.self, forKey: .note)
            tagIDs = try values.decode([String].self, forKey: .tagIDs)
            frequency = try values.decode(String.self, forKey: .frequency)
            startDateSecondsSince2001 = try values.decode(Double.self, forKey: .startDateSecondsSince2001)
            // A missing cursor or boundary must not silently restart an imported schedule.
            endDateSecondsSince2001 = try values.decode(Double?.self, forKey: .endDateSecondsSince2001)
            lastGeneratedDateSecondsSince2001 = try values.decode(Double?.self, forKey: .lastGeneratedDateSecondsSince2001)
            recurrenceTimeZoneIdentifier = try values.decode(String?.self, forKey: .recurrenceTimeZoneIdentifier)
            recurrenceEffectiveDateSecondsSince2001 = try values.decode(Double?.self, forKey: .recurrenceEffectiveDateSecondsSince2001)
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(id, forKey: .id)
            try values.encode(name, forKey: .name)
            try values.encode(amount, forKey: .amount)
            try values.encode(category, forKey: .category)
            try values.encode(note, forKey: .note)
            try values.encode(tagIDs, forKey: .tagIDs)
            try values.encode(frequency, forKey: .frequency)
            try values.encode(startDateSecondsSince2001, forKey: .startDateSecondsSince2001)
            try values.encode(endDateSecondsSince2001, forKey: .endDateSecondsSince2001)
            try values.encode(lastGeneratedDateSecondsSince2001, forKey: .lastGeneratedDateSecondsSince2001)
            try values.encode(recurrenceTimeZoneIdentifier, forKey: .recurrenceTimeZoneIdentifier)
            try values.encode(recurrenceEffectiveDateSecondsSince2001, forKey: .recurrenceEffectiveDateSecondsSince2001)
        }
    }

    public struct Tag: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var appearance: Appearance?

        public init(id: String, name: String, appearance: Appearance? = nil) {
            self.id = id
            self.name = name
            self.appearance = appearance
        }

        @MainActor init(tag: ExpenseTag) throws {
            id = tag.id.uuidString.lowercased()
            name = tag.name
            appearance = try Appearance(color: tag.uiColor, emoji: tag.emoji, symbolName: tag.symbolName)
        }

        public struct Appearance: Codable, Equatable, Sendable {
            public var emoji: String
            public var symbolName: String?
            // Extended sRGB RGBA preserves wide-gamut colors without clipping to 0...1.
            public var light: [Double]
            public var dark: [Double]

            @MainActor init(color: UIColor, emoji: String, symbolName: String?) throws {
                self.emoji = emoji
                self.symbolName = symbolName
                func components(_ style: UIUserInterfaceStyle) throws -> [Double] {
                    guard let converted = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).cgColor
                        .converted(to: CGColorSpace(name: CGColorSpace.extendedSRGB)!, intent: .defaultIntent, options: nil),
                          let values = converted.components, values.count == 4 else {
                        throw ExpenseBackupError.invalid("tag color cannot be exported.")
                    }
                    return values.map(Double.init)
                }
                light = try components(.light)
                dark = try components(.dark)
            }

            @MainActor var uiColor: UIColor {
                let lightColor = UIColor(cgColor: CGColor(colorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!, components: light.map { CGFloat($0) })!)
                let darkColor = UIColor(cgColor: CGColor(colorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!, components: dark.map { CGFloat($0) })!)
                if light == dark { return lightColor }
                return UIColor { traits in traits.userInterfaceStyle == .dark ? darkColor : lightColor }
            }
        }
    }

    public struct Record: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var dateSecondsSince2001: Double
        public var amount: String
        public var category: String
        public var note: String
        public var tagIDs: [String]
        public var recurringExpenseID: String?
        public var recurringOccurrenceKey: String?

        public init(id: String, name: String, dateSecondsSince2001: Double, amount: String, category: String,
                    note: String, tagIDs: [String], recurringExpenseID: String? = nil, recurringOccurrenceKey: String? = nil) {
            self.id = id
            self.name = name
            self.dateSecondsSince2001 = dateSecondsSince2001
            self.amount = amount
            self.category = category
            self.note = note
            self.tagIDs = tagIDs
            self.recurringExpenseID = recurringExpenseID
            self.recurringOccurrenceKey = recurringOccurrenceKey
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, dateSecondsSince2001, amount, category, note, tagIDs, recurringExpenseID, recurringOccurrenceKey
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            name = try values.decode(String.self, forKey: .name)
            dateSecondsSince2001 = try values.decode(Double.self, forKey: .dateSecondsSince2001)
            amount = try values.decode(String.self, forKey: .amount)
            category = try values.decode(String.self, forKey: .category)
            note = try values.decode(String.self, forKey: .note)
            tagIDs = try values.decode([String].self, forKey: .tagIDs)
            // decode(Optional.self), rather than decodeIfPresent, requires the nullable keys.
            recurringExpenseID = try values.decode(String?.self, forKey: .recurringExpenseID)
            recurringOccurrenceKey = try values.decode(String?.self, forKey: .recurringOccurrenceKey)
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(id, forKey: .id)
            try values.encode(name, forKey: .name)
            try values.encode(dateSecondsSince2001, forKey: .dateSecondsSince2001)
            try values.encode(amount, forKey: .amount)
            try values.encode(category, forKey: .category)
            try values.encode(note, forKey: .note)
            try values.encode(tagIDs, forKey: .tagIDs)
            try values.encode(recurringExpenseID, forKey: .recurringExpenseID)
            try values.encode(recurringOccurrenceKey, forKey: .recurringOccurrenceKey)
        }

        public var date: Date { Date(timeIntervalSinceReferenceDate: dateSecondsSince2001) }

        public var effectiveOccurrenceKey: String? {
            guard let rawRule = recurringExpenseID, let rule = UUID(uuidString: rawRule) else { return nil }
            return recurringOccurrenceKey ?? RecurringExpenseOccurrence.safeKey(ruleID: rule, scheduledDate: date)
        }
    }
}

public nonisolated enum ExpenseBackupError: LocalizedError, Equatable {
    case invalid(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalid(let detail): "Invalid expense backup: \(detail)"
        case .unsupportedVersion(let version): "Expense backup version \(version) is not supported. Update Syl before importing this file."
        }
    }
}

public nonisolated enum ExpenseBackupCodec {
    public static func decode(_ data: Data) throws -> ExpenseBackup {
        struct Header: Decodable { let format: String; let version: Int }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.format == "sage.expense-backup" else { throw ExpenseBackupError.invalid("unrecognized format.") }
        guard [1, 2].contains(header.version) else { throw ExpenseBackupError.unsupportedVersion(header.version) }
        let backup = try JSONDecoder().decode(ExpenseBackup.self, from: data)
        try validate(backup)
        return backup
    }

    public static func encode(_ backup: ExpenseBackup) throws -> Data {
        try validate(backup)
        var canonical = backup
        canonical.tags = backup.tags.map { .init(id: $0.id.lowercased(), name: $0.name, appearance: $0.appearance) }.sorted { $0.id < $1.id }
        canonical.expenses = backup.expenses.map { record in
            var record = record
            record.id = record.id.lowercased()
            record.tagIDs = record.tagIDs.map { $0.lowercased() }.sorted()
            record.recurringExpenseID = record.recurringExpenseID?.lowercased()
            record.amount = String(Double(record.amount)!)
            return record
        }.sorted { $0.id < $1.id }
        canonical.recurringRules = backup.recurringRules.map { rule in
            var rule = rule
            rule.id = rule.id.lowercased()
            rule.tagIDs = rule.tagIDs.map { $0.lowercased() }.sorted()
            rule.amount = String(Double(rule.amount)!)
            return rule
        }.sorted { $0.id < $1.id }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(canonical)
    }

    public static func validate(_ backup: ExpenseBackup) throws {
        guard backup.format == "sage.expense-backup" else { throw ExpenseBackupError.invalid("unrecognized format.") }
        guard [1, 2].contains(backup.version) else { throw ExpenseBackupError.unsupportedVersion(backup.version) }
        guard backup.version >= 2 || backup.recurringRules.isEmpty else {
            throw ExpenseBackupError.invalid("version 1 cannot contain recurring rules.")
        }
        guard LedgerCurrency.validatedCode(backup.currency) != nil else { throw ExpenseBackupError.invalid("unsupported currency.") }
        func uuid(_ value: String) throws -> UUID {
            guard let id = UUID(uuidString: value), id.uuidString.lowercased() == value.lowercased() else {
                throw ExpenseBackupError.invalid("invalid UUID '\(value)'.")
            }
            return id
        }
        var tags = Set<UUID>()
        for tag in backup.tags {
            guard try tags.insert(uuid(tag.id)).inserted else { throw ExpenseBackupError.invalid("duplicate tag ID.") }
            if let appearance = tag.appearance {
                for components in [appearance.light, appearance.dark] {
                    guard components.count == 4,
                          components.allSatisfy({ $0.isFinite && abs($0) <= Double(Float.greatestFiniteMagnitude) }),
                          (0...1).contains(components[3]) else {
                        throw ExpenseBackupError.invalid("invalid tag color components.")
                    }
                }
            }
        }
        var expenses = Set<UUID>()
        var occurrences = Set<String>()
        var referencedTags = Set<UUID>()
        for record in backup.expenses {
            guard try expenses.insert(uuid(record.id)).inserted else { throw ExpenseBackupError.invalid("duplicate expense ID.") }
            guard record.dateSecondsSince2001.isFinite, RecurringExpenseOccurrence.safeMilliseconds(record.date) != nil else {
                throw ExpenseBackupError.invalid("unsafe expense date.")
            }
            // Backups preserve saved zero-value records even though new entry rejects zero.
            guard let amount = Double(record.amount), amount.isFinite, abs(amount) <= MonetaryAmount.maximumMagnitude else {
                throw ExpenseBackupError.invalid("expense '\(record.name)' (ID: \(record.id)) has amount '\(record.amount)'. Amounts must be finite and no more than 1 billion in magnitude. No records were omitted or changed.")
            }
            guard ExpenseCategory(rawValue: record.category) != nil else { throw ExpenseBackupError.invalid("unknown category.") }
            var recordTags = Set<UUID>()
            for value in record.tagIDs {
                let id = try uuid(value)
                guard tags.contains(id), recordTags.insert(id).inserted else { throw ExpenseBackupError.invalid("missing or repeated tag reference.") }
            }
            referencedTags.formUnion(recordTags)
            if let rawRule = record.recurringExpenseID {
                let rule = try uuid(rawRule)
                if let key = record.recurringOccurrenceKey, !RecurringExpenseOccurrence.isValidKey(key, ruleID: rule) {
                    throw ExpenseBackupError.invalid("invalid recurrence identity.")
                }
                guard let key = record.effectiveOccurrenceKey, occurrences.insert(key).inserted else {
                    throw ExpenseBackupError.invalid("duplicate or unsafe occurrence identity.")
                }
            } else if record.recurringOccurrenceKey != nil {
                throw ExpenseBackupError.invalid("occurrence key requires a rule ID.")
            }
        }
        var rules = Set<UUID>()
        for rule in backup.recurringRules {
            guard try rules.insert(uuid(rule.id)).inserted else { throw ExpenseBackupError.invalid("duplicate recurring rule ID.") }
            guard let amount = Double(rule.amount), amount.isFinite, abs(amount) <= MonetaryAmount.maximumMagnitude else {
                throw ExpenseBackupError.invalid("recurring rule '\(rule.name)' (ID: \(rule.id)) has amount '\(rule.amount)'. Amounts must be finite and no more than 1 billion in magnitude. No records were omitted or changed.")
            }
            guard ExpenseCategory(rawValue: rule.category) != nil, RecurrenceFrequency(rawValue: rule.frequency) != nil else {
                throw ExpenseBackupError.invalid("unknown recurring category or frequency.")
            }
            for seconds in [rule.startDateSecondsSince2001, rule.endDateSecondsSince2001,
                            rule.lastGeneratedDateSecondsSince2001, rule.recurrenceEffectiveDateSecondsSince2001].compactMap({ $0 }) {
                guard seconds.isFinite, seconds >= Date.distantPast.timeIntervalSinceReferenceDate,
                      seconds <= Date.distantFuture.timeIntervalSinceReferenceDate else {
                    throw ExpenseBackupError.invalid("unsafe recurring rule date.")
                }
            }
            if let zone = rule.recurrenceTimeZoneIdentifier, TimeZone(identifier: zone) == nil {
                throw ExpenseBackupError.invalid("unknown recurring time zone.")
            }
            var ruleTags = Set<UUID>()
            for value in rule.tagIDs {
                let id = try uuid(value)
                guard tags.contains(id), ruleTags.insert(id).inserted else { throw ExpenseBackupError.invalid("missing or repeated recurring tag reference.") }
            }
            referencedTags.formUnion(ruleTags)
        }
        guard tags == referencedTags else { throw ExpenseBackupError.invalid("unused tag definitions.") }
    }

    /// Reads only saved data. Never saves, repairs, or examines the UI context.
    @MainActor public static func snapshot(modelContainer: ModelContainer, currency: String) throws -> ExpenseBackup {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let persistedTags = Dictionary(grouping: try context.fetch(FetchDescriptor<ExpenseTag>()), by: \.id)
        var tags: [UUID: ExpenseBackup.Tag] = [:]
        let records = try expenses.map { expense in
            let selected = (expense.tags?.isEmpty == false ? expense.tags : expense.tag.map { [$0] }) ?? []
            for tag in selected {
                guard persistedTags[tag.id]?.count == 1 else { throw ExpenseBackupError.invalid("duplicate or missing persisted tag ID.") }
                tags[tag.id] = try .init(tag: tag)
            }
            // Preserve moved, keyless legacy occurrences using the existing backup format.
            var occurrenceKey = expense.recurringOccurrenceKey
            if occurrenceKey == nil, let ruleID = expense.recurringExpenseId,
               let scheduledDate = expense.recurringScheduledDate, scheduledDate != expense.date {
                occurrenceKey = RecurringExpenseOccurrence.safeKey(ruleID: ruleID, scheduledDate: scheduledDate)
            }
            return ExpenseBackup.Record(
                id: expense.id.uuidString.lowercased(), name: expense.name,
                dateSecondsSince2001: expense.date.timeIntervalSinceReferenceDate, amount: String(expense.amount),
                category: expense.category.rawValue, note: expense.note, tagIDs: selected.map { $0.id.uuidString.lowercased() },
                recurringExpenseID: expense.recurringExpenseId?.uuidString.lowercased(), recurringOccurrenceKey: occurrenceKey
            )
        }
        let rules = try context.fetch(FetchDescriptor<RecurringExpenseRule>()).map { rule in
            let selected = (rule.tags?.isEmpty == false ? rule.tags : rule.tag.map { [$0] }) ?? []
            for tag in selected {
                guard persistedTags[tag.id]?.count == 1 else { throw ExpenseBackupError.invalid("duplicate or missing persisted tag ID.") }
                tags[tag.id] = try .init(tag: tag)
            }
            return ExpenseBackup.Rule(
                id: rule.id.uuidString.lowercased(), name: rule.name, amount: String(rule.amount),
                category: rule.category.rawValue, note: rule.note, tagIDs: selected.map { $0.id.uuidString.lowercased() },
                frequency: rule.frequency.rawValue, startDateSecondsSince2001: rule.startDate.timeIntervalSinceReferenceDate,
                endDateSecondsSince2001: rule.endDate?.timeIntervalSinceReferenceDate,
                lastGeneratedDateSecondsSince2001: rule.lastGeneratedDate?.timeIntervalSinceReferenceDate,
                recurrenceTimeZoneIdentifier: rule.recurrenceTimeZoneIdentifier,
                recurrenceEffectiveDateSecondsSince2001: rule.recurrenceEffectiveDate?.timeIntervalSinceReferenceDate
            )
        }
        let backup = ExpenseBackup(currency: currency, tags: Array(tags.values), expenses: records, recurringRules: rules)
        try validate(backup)
        return backup
    }
}
