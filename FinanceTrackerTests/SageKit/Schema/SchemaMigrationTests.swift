import SQLite3
import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Schema migration", .serialized)
struct SchemaMigrationTests {
    @Test @MainActor
    func freshStoreCreatesExpenseDateIndexes() throws {
        UIColorValueTransformer.register()
        let directory = FileManager.default.temporaryDirectory.appending(path: "SageIndexes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Indexes.sqlite")
        let schema = Schema(versionedSchema: SageSchemaV9.self)
        let container = try ModelContainer(for: schema, migrationPlan: SageSchemaMigrationPlan.self, configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ])
        container.mainContext.insert(Expense(name: "Indexed expense", amount: 42))
        try container.mainContext.save()
        try expectExpenseDateIndexes(at: url)
    }

    @Test @MainActor
    func v1StoreMigratesToCurrentSchema() throws {
        UIColorValueTransformer.register()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SageMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Migration.sqlite")

        try createV1Store(at: storeURL)

        let schema = Schema(versionedSchema: SageSchemaV9.self)
        let configuration = ModelConfiguration(
            "Migration",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SageSchemaMigrationPlan.self,
            configurations: [configuration]
        )
        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())

        #expect(expenses.count == 1)
        let expense = try #require(expenses.first)
        #expect(expense.name == "Legacy Rent")
        #expect(expense.amount == 900)
        #expect(expense.category == .needs)
        #expect(expense.note == "V1 record")
        #expect(expense.account == nil)
        #expect(expense.recurringOccurrenceKey == nil)
        #expect(expense.recurringScheduledDate == nil)
        let rule = try #require(container.mainContext.fetch(FetchDescriptor<RecurringExpenseRule>()).first)
        #expect(rule.name == "Legacy Rule")
        #expect(rule.recurrenceTimeZoneIdentifier == nil)
        #expect(rule.recurrenceEffectiveDate == nil)
    }

    @Test @MainActor
    func v5RecurringStoreMigratesWithoutChangingScheduleOrKeys() throws {
        UIColorValueTransformer.register()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SageMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Migration.sqlite")
        let ruleID = UUID()
        let expenseID = UUID()
        let start = Date(timeIntervalSince1970: 1_769_860_800)
        let cursor = start.addingTimeInterval(28 * 86_400)
        let key = RecurringExpenseOccurrence.key(ruleID: ruleID, scheduledDate: cursor)
        try createV5Store(at: url, ruleID: ruleID, expenseID: expenseID, start: start, cursor: cursor, key: key)

        // Reopen both the migrated legacy rule and its explicitly converted schedule.
        for opening in 0..<3 {
            let schema = Schema(versionedSchema: SageSchemaV9.self)
            let configuration = ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: SageSchemaMigrationPlan.self, configurations: [configuration])
            let rule = try #require(container.mainContext.fetch(FetchDescriptor<RecurringExpenseRule>()).first)
            let expense = try #require(container.mainContext.fetch(FetchDescriptor<Expense>()).first)
            #expect(rule.id == ruleID)
            #expect(rule.startDate == start)
            #expect(rule.lastGeneratedDate == cursor)
            #expect(rule.endDate == cursor.addingTimeInterval(365 * 86_400))
            #expect(rule.frequency == .monthly)
            if opening < 2 {
                #expect(rule.recurrenceTimeZoneIdentifier == nil)
                #expect(rule.recurrenceEffectiveDate == nil)
            } else {
                #expect(rule.recurrenceTimeZoneIdentifier == TimeZone(secondsFromGMT: 0)!.identifier)
                #expect(rule.recurrenceEffectiveDate == cursor)
            }
            #expect(rule.tags?.first?.name == "Bills")
            #expect(rule.account?.name == "Bank")
            #expect(expense.id == expenseID)
            #expect(expense.recurringExpenseId == ruleID)
            #expect(expense.recurringOccurrenceKey == key)
            #expect(expense.recurringScheduledDate == cursor)
            #expect(expense.date == cursor.addingTimeInterval(60))
            #expect(expense.tags?.first?.id == rule.tags?.first?.id)
            #expect(expense.account?.id == rule.account?.id)
            if opening == 1 {
                rule.enableFixedSchedule(in: TimeZone(secondsFromGMT: 0)!, after: cursor, existingExpenses: [expense])
                try container.mainContext.save()
            }
        }
    }

    @Test @MainActor
    func v6ScheduledDatesBackfillAndRemainStableOnReopen() throws {
        UIColorValueTransformer.register()
        let directory = FileManager.default.temporaryDirectory.appending(path: "SageMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Migration.sqlite")
        let scheduled = Date(timeIntervalSince1970: 1_786_368_000.125)
        let edited = scheduled.addingTimeInterval(40 * 86_400)
        let ruleID = UUID()
        let key = RecurringExpenseOccurrence.key(ruleID: ruleID, scheduledDate: scheduled)
        do {
            let schema = Schema(versionedSchema: SageSchemaV6.self)
            let container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
            ])
            container.mainContext.insert(SageSchemaV6.Expense(name: "Moved", amount: 10, date: edited,
                                                             recurringExpenseId: ruleID, recurringOccurrenceKey: key))
            container.mainContext.insert(SageSchemaV6.Expense(name: "Legacy", amount: 20, date: scheduled,
                                                             recurringExpenseId: ruleID))
            container.mainContext.insert(SageSchemaV6.Expense(name: "Manual", amount: 30, date: scheduled))
            try container.mainContext.save()
        }
        for opening in 0..<2 {
            let schema = Schema(versionedSchema: SageSchemaV9.self)
            let container = try ModelContainer(for: schema, migrationPlan: SageSchemaMigrationPlan.self, configurations: [
                ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
            ])
            let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
            #expect(expenses.count == 3)
            let moved = try #require(expenses.first { $0.name == "Moved" })
            let legacy = try #require(expenses.first { $0.name == "Legacy" })
            #expect(moved.recurringScheduledDate == scheduled)
            #expect(moved.recurringOccurrenceKey == key)
            #expect(moved.date == edited)
            #expect(legacy.recurringScheduledDate == scheduled)
            #expect(legacy.recurringOccurrenceKey == nil)
            #expect(legacy.date == (opening == 0 ? scheduled : edited))
            #expect(expenses.first { $0.name == "Manual" }?.recurringScheduledDate == nil)
            if opening == 0 {
                legacy.date = edited
                try container.mainContext.save()
            }
            let matches = try container.mainContext.fetch(ExpenseFetchDescriptors.recurringScheduled(in: scheduled))
            #expect(Set(matches.map(\.name)) == ["Moved", "Legacy"])
            try expectExpenseDateIndexes(at: url)
        }
    }

    @Test @MainActor
    func v7MigrationInstallsDateIndexAndPreservesRecords() throws {
        UIColorValueTransformer.register()
        let directory = FileManager.default.temporaryDirectory.appending(path: "SageV7Migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Migration.sqlite")
        let expenseID = UUID()
        let ruleID = UUID()
        let scheduled = Date(timeIntervalSince1970: 1_786_368_000.125)
        let edited = scheduled.addingTimeInterval(40 * 86_400)
        let key = RecurringExpenseOccurrence.key(ruleID: ruleID, scheduledDate: scheduled)
        do {
            let schema = Schema(versionedSchema: SageSchemaV7.self)
            let container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
            ])
            let tag = SageSchemaV7.ExpenseTag(name: "Bills", uiColor: .blue, emoji: "B")
            let account = SageSchemaV7.ExpenseAccount(id: UUID(), name: "Bank", type: .bankAccount)
            let rule = SageSchemaV7.RecurringExpenseRule(name: "Rent", amount: 900, note: "Rule", category: .needs,
                tags: [tag], frequency: .monthly, startDate: scheduled, lastGeneratedDate: scheduled,
                recurrenceTimeZoneIdentifier: "GMT")
            rule.id = ruleID
            rule.account = account
            rule.recurrenceEffectiveDate = scheduled
            let expense = SageSchemaV7.Expense(name: "Moved rent", amount: 901.25, category: .needs, date: edited,
                tags: [tag], note: "Edited", recurringExpenseId: ruleID, recurringOccurrenceKey: key, account: account)
            expense.id = expenseID
            container.mainContext.insert(rule)
            container.mainContext.insert(expense)
            try container.mainContext.save()
            try expectExpenseDateIndexes(at: url, hasDateIndex: false)
        }
        for _ in 0..<2 {
            let schema = Schema(versionedSchema: SageSchemaV9.self)
            let container = try ModelContainer(for: schema, migrationPlan: SageSchemaMigrationPlan.self, configurations: [
                ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
            ])
            let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
            #expect(expenses.count == 1)
            let expense = try #require(expenses.first)
            let rule = try #require(container.mainContext.fetch(FetchDescriptor<RecurringExpenseRule>()).first)
            #expect(expense.id == expenseID)
            #expect(expense.name == "Moved rent" && expense.amount == 901.25 && expense.category == .needs)
            #expect(expense.note == "Edited" && expense.date == edited)
            #expect(expense.recurringScheduledDate == scheduled && expense.recurringOccurrenceKey == key)
            #expect(expense.recurringExpenseId == ruleID)
            #expect(rule.id == ruleID && rule.frequency == .monthly && rule.startDate == scheduled)
            #expect(rule.lastGeneratedDate == scheduled && rule.recurrenceEffectiveDate == scheduled)
            #expect(rule.recurrenceTimeZoneIdentifier == "GMT")
            #expect(expense.tags?.first?.name == "Bills")
            #expect(expense.tags?.first?.id == rule.tags?.first?.id)
            #expect(expense.account?.name == "Bank")
            #expect(expense.account?.id == rule.account?.id)
            try expectExpenseDateIndexes(at: url)
        }
    }

    @Test @MainActor
    func v8MigrationDefaultsTagVisibilityAndPreservesRecordsOnReopen() throws {
        UIColorValueTransformer.register()
        let directory = FileManager.default.temporaryDirectory.appending(path: "SageV8Migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Migration.sqlite")
        let tagID = UUID()
        let accountID = UUID()
        let ruleID = UUID()
        let expenseID = UUID()
        let scheduled = Date(timeIntervalSince1970: 1_786_368_000.125)
        let edited = scheduled.addingTimeInterval(40 * 86_400)
        let key = RecurringExpenseOccurrence.key(ruleID: ruleID, scheduledDate: scheduled)

        try autoreleasepool {
            let schema = Schema(versionedSchema: SageSchemaV8.self)
            let container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
            ])
            let tag = SageSchemaV8.ExpenseTag(id: tagID, name: "Bills", uiColor: .blue, emoji: "B",
                                             symbolName: "house.fill", budget: 1_200)
            let account = SageSchemaV8.ExpenseAccount(id: accountID, name: "Bank", type: .bankAccount)
            let rule = SageSchemaV8.RecurringExpenseRule(name: "Rent", amount: 900, note: "Rule", category: .needs,
                tags: [tag], frequency: .monthly, startDate: scheduled, lastGeneratedDate: scheduled,
                recurrenceTimeZoneIdentifier: "GMT")
            rule.id = ruleID
            rule.account = account
            rule.recurrenceEffectiveDate = scheduled
            let expense = SageSchemaV8.Expense(name: "Moved rent", amount: 901.25, category: .needs, date: edited,
                tags: [tag], note: "Edited", recurringExpenseId: ruleID, recurringOccurrenceKey: key, account: account)
            expense.id = expenseID
            container.mainContext.insert(rule)
            container.mainContext.insert(expense)
            try container.mainContext.save()
        }

        for opening in 0..<2 {
            try autoreleasepool {
                let schema = Schema(versionedSchema: SageSchemaV9.self)
                let container = try ModelContainer(for: schema, migrationPlan: SageSchemaMigrationPlan.self, configurations: [
                    ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
                ])
                let context = container.mainContext
                let tags = try context.fetch(FetchDescriptor<ExpenseTag>())
                let expenses = try context.fetch(FetchDescriptor<Expense>())
                let rules = try context.fetch(FetchDescriptor<RecurringExpenseRule>())
                let accounts = try context.fetch(FetchDescriptor<ExpenseAccount>())
                #expect(tags.count == 1 && expenses.count == 1 && rules.count == 1 && accounts.count == 1)
                let tag = try #require(tags.first)
                let expense = try #require(expenses.first)
                let rule = try #require(rules.first)
                let account = try #require(accounts.first)
                #expect(tag.id == tagID && tag.name == "Bills" && tag.emoji == "B")
                #expect(tag.symbolName == "house.fill" && tag.budget == 1_200 && tag.uiColor == UIColor.blue)
                #expect(tag.isHiddenFromExpenseEntry == (opening == 1))
                #expect(expense.id == expenseID && expense.name == "Moved rent" && expense.amount == 901.25)
                #expect(expense.category == .needs && expense.note == "Edited" && expense.date == edited)
                #expect(expense.recurringExpenseId == ruleID && expense.recurringOccurrenceKey == key)
                #expect(expense.recurringScheduledDate == scheduled)
                #expect(rule.id == ruleID && rule.name == "Rent" && rule.amount == 900 && rule.note == "Rule")
                #expect(rule.category == .needs && rule.frequency == .monthly && rule.startDate == scheduled)
                #expect(rule.lastGeneratedDate == scheduled && rule.recurrenceEffectiveDate == scheduled)
                #expect(rule.recurrenceTimeZoneIdentifier == "GMT")
                #expect(account.id == accountID && account.name == "Bank" && account.type == .bankAccount)
                #expect(expense.tags?.map(\.id) == [tagID] && rule.tags?.map(\.id) == [tagID])
                #expect(expense.account?.id == accountID && rule.account?.id == accountID)
                #expect(tag.taggedExpenses?.map(\.id) == [expenseID])
                #expect(tag.taggedRecurringRules?.map(\.id) == [ruleID])
                try expectExpenseDateIndexes(at: url)

                if opening == 0 {
                    tag.isHiddenFromExpenseEntry = true
                    try context.save()
                }
            }
        }
    }

    private func expectExpenseDateIndexes(at url: URL, hasDateIndex: Bool = true) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(database) }
        try #require(result == SQLITE_OK)
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(database,
            "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = 'ZEXPENSE'",
            -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var indexes: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let sql = sqlite3_column_text(statement, 0) {
                indexes.append(String(cString: sql))
            }
        }
        #expect(indexes.contains { $0.contains("(ZDATE ") } == hasDateIndex)
        #expect(indexes.contains { $0.contains("(ZRECURRINGSCHEDULEDDATE ") })
    }

    private func createV5Store(at url: URL, ruleID: UUID, expenseID: UUID, start: Date, cursor: Date, key: String) throws {
        let schema = Schema(versionedSchema: SageSchemaV5.self)
        let configuration = ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let tag = SageSchemaV5.ExpenseTag(name: "Bills", uiColor: .blue, emoji: "B")
        let account = SageSchemaV5.ExpenseAccount(id: UUID(), name: "Bank", type: .bankAccount)
        let rule = SageSchemaV5.RecurringExpenseRule(name: "Rent", amount: 900, note: "Legacy", category: .needs, tags: [tag], frequency: .monthly, startDate: start, endDate: cursor.addingTimeInterval(365 * 86_400), lastGeneratedDate: cursor)
        rule.id = ruleID
        rule.account = account
        let expense = SageSchemaV5.Expense(name: "Rent", amount: 900, date: cursor.addingTimeInterval(60), tags: [tag], recurringExpenseId: ruleID, recurringOccurrenceKey: key, account: account)
        expense.id = expenseID
        context.insert(tag)
        context.insert(account)
        context.insert(rule)
        context.insert(expense)
        try context.save()
    }

    private func createV1Store(at url: URL) throws {
        let schema = Schema(versionedSchema: SageSchemaV1.self)
        let configuration = ModelConfiguration(
            "Migration",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(
            SageSchemaV1.Expense(
                name: "Legacy Rent",
                amount: 900,
                category: .needs,
                note: "V1 record"
            )
        )
        let tag = SageSchemaV1.ExpenseTag(name: "Bills", uiColor: .blue, emoji: "B")
        context.insert(tag)
        context.insert(SageSchemaV1.RecurringExpenseRule(name: "Legacy Rule", amount: 900, note: "", category: .needs, tag: tag, frequency: .monthly, startDate: Date(timeIntervalSince1970: 1_769_860_800)))
        try context.save()
    }
}
