//
//  SageModelContainer.swift
//  FinanceTracker
//
//  Created by Enzo on 5/21/26.
//

import Foundation
import OSLog
import SwiftData
import Synchronization

public enum SageModelContainer {
    public enum Purpose: Sendable {
        case app
        case test
        case preview
        case previewEmpty
    }

    public enum Error: LocalizedError, Equatable {
        case appGroupUnavailable
        /// Opening without iCloud sync was already tried and also failed.
        case unavailableWithoutCloudSync(NSError)

        public var errorDescription: String? {
            switch self {
            case .appGroupUnavailable:
                return "The shared app storage is unavailable."
            case let .unavailableWithoutCloudSync(error):
                return error.localizedDescription
            }
        }
    }

    public nonisolated static let appGroupIdentifier = "group.me.enzottic.SageAppGroup"
    #if DEBUG
    public nonisolated static let supportsCloudSync = false
    #else
    public nonisolated static let supportsCloudSync = true
    #endif

    // The app, widgets, and App Intents use the same fixed configuration.
    @MainActor
    public static let shared: Result<ModelContainer, any Swift.Error> = Result {
        try make(for: .app)
    }

    public static nonisolated func make(for purpose: Purpose = .app) throws -> ModelContainer {
        UIColorValueTransformer.register()

        let schema = Schema(versionedSchema: SageSchemaV10.self)
        let container: ModelContainer
        do {
            container = try openContainer(schema: schema, configuration: configuration(for: purpose, schema: schema))
            if case .app = purpose, supportsCloudSync {
                isCloudSyncPaused = false
            }
        } catch where purpose == .app && supportsCloudSync && isCloudSyncPaused {
            do {
                container = try openContainer(schema: schema, configuration: appConfiguration(schema: schema, cloudKit: false))
                openedWithoutCloudSync.withLock { $0 = true }
            } catch {
                throw Error.unavailableWithoutCloudSync(error as NSError)
            }
        }

        if case .app = purpose {
            do {
                try backfillMultiTags(container)
            } catch {
                logger.error("Legacy tag backfill failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        return container
    }

    /// Set from the recovery screen when the iCloud-backed store can't open, so Syl opens the same
    /// store without sync. Every launch still tries iCloud first and clears this once that works.
    public nonisolated static var isCloudSyncPaused: Bool {
        get { UserDefaults(suiteName: appGroupIdentifier)?.bool(forKey: cloudSyncPausedKey) ?? false }
        set { UserDefaults(suiteName: appGroupIdentifier)?.set(newValue, forKey: cloudSyncPausedKey) }
    }

    /// Whether this process opened the store without sync. Another process (a widget) can clear
    /// `isCloudSyncPaused` while this one keeps running without sync.
    public nonisolated static var isRunningWithoutCloudSync: Bool {
        openedWithoutCloudSync.withLock { $0 }
    }

    private nonisolated static let openedWithoutCloudSync = Mutex(false)
    private nonisolated static let cloudSyncPausedKey = "cloudSyncPausedAfterStoreFailure"
    private nonisolated static let logger = Logger(subsystem: "me.enzottic.FinanceTracker", category: "Persistence")

    private static nonisolated func openContainer(schema: Schema, configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: SageSchemaMigrationPlan.self, configurations: [configuration])
    }

    private static nonisolated func configuration(
        for purpose: Purpose,
        schema: Schema
    ) throws -> ModelConfiguration {
        switch purpose {
        case .test, .preview, .previewEmpty:
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        case .app:
            return try appConfiguration(schema: schema)
        }
    }

    private static nonisolated func appConfiguration(
        schema: Schema,
        cloudKit: Bool = true
    ) throws -> ModelConfiguration {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw Error.appGroupUnavailable
        }

        #if DEBUG
        return ModelConfiguration(
            "SageDev",
            schema: schema,
            url: groupURL.appending(path: "SageDev.sqlite"),
            cloudKitDatabase: .none
        )
        #else
        let storeURL = groupURL.appending(path: "Sage.sqlite")
        return ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: cloudKit ? .automatic : .none
        )
        #endif
    }

    // Migrates legacy single-tag data into the V3 `tags` array.
    static nonisolated func backfillMultiTags(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        for expense in expenses {
            if let legacyTag = expense.tag {
                if (expense.tags ?? []).isEmpty {
                    expense.tags = [legacyTag]
                }
                expense.tag = nil
            }
        }

        let rules = try context.fetch(FetchDescriptor<RecurringExpenseRule>())
        for rule in rules {
            if let legacyTag = rule.tag {
                if (rule.tags ?? []).isEmpty {
                    rule.tags = [legacyTag]
                }
                rule.tag = nil
            }
        }

        // Conversion and consumption are one transaction. An explicit modern selection
        // wins; consuming its stale legacy value also prevents later tag resurrection.
        // No global flag: legacy-only records arriving later still need conversion.
        // Older clients can write `tag` again via CloudKit; without a per-record
        // synchronized tombstone we cannot distinguish that from a late legacy record.
        if context.hasChanges {
            try context.save()
        }
    }
}
