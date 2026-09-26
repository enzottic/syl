import CoreData
import Foundation
import OSLog
import SageKit
import SwiftData
import UIKit
import WidgetKit

@MainActor
final class RecurringExpenseCoordinator {
    private static let logger = Logger(
        subsystem: "me.enzottic.FinanceTracker",
        category: "RecurringExpenses"
    )

    private let modelContext: ModelContext
    private let cloudKitEnabled: Bool
    private var observers: [NSObjectProtocol] = []
    private var maintenanceTask: Task<Void, Never>?
    private var hasStarted = false
    private var hasAttemptedMaintenance = false
    private var retryDelay: UInt64 = 5_000_000_000
    private var importIsActive = false

    init(modelContainer: ModelContainer, cloudKitEnabled: Bool) {
        self.modelContext = ModelContext(modelContainer)
        self.modelContext.autosaveEnabled = false
        self.cloudKitEnabled = cloudKitEnabled
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        observeCloudKitEvents()
        observeAppActivation()

        if cloudKitEnabled {
            // The import completion event normally starts maintenance. This fallback also lets
            // recurring expenses work when the device starts without a network connection.
            scheduleMaintenance(afterNanoseconds: 30_000_000_000)
        } else {
            scheduleMaintenance(afterNanoseconds: 0)
        }
    }

    private func observeCloudKitEvents() {
        let observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            
            guard let
                event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                event.type == .import else { return }

            Task { @MainActor [weak self] in
                self?.handleImportEvent(event)
            }
        }
        
        observers.append(observer)
    }

    private func observeAppActivation() {
        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.hasAttemptedMaintenance, !self.importIsActive else { return }
                self.scheduleMaintenance(afterNanoseconds: 1_000_000_000)
            }
        }
        observers.append(observer)
    }

    private func handleImportEvent(_ event: NSPersistentCloudKitContainer.Event) {
        if event.endDate == nil {
            importIsActive = true
            maintenanceTask?.cancel()
            return
        }

        importIsActive = false
        if event.succeeded {
            scheduleMaintenance(afterNanoseconds: 500_000_000)
        } else {
            scheduleMaintenance(afterNanoseconds: 5_000_000_000)
        }
    }

    private func scheduleMaintenance(afterNanoseconds delay: UInt64) {
        maintenanceTask?.cancel()
        maintenanceTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled, let self, !self.importIsActive else { return }
            self.runMaintenance()
        }
    }

    private func runMaintenance() {
        hasAttemptedMaintenance = true
        
        do {
            let result = try RecurringExpenseService(modelContext: modelContext)
                .generateAllExpenses(through: .now)
            retryDelay = 5_000_000_000

            Self.logger.info(
                "Recurring maintenance completed. Generated: \(result.generatedCount), skipped: \(result.skippedCount), repaired: \(result.repair.removedCount)."
            )

            if result.generatedCount > 0 || result.repair.removedCount > 0 {
                WidgetCenter.shared.reloadAllTimelines()
            }
            
            // Also handles rules becoming due while the app stays in the foreground.
            let now = Date.now
            let rules = try modelContext.fetch(FetchDescriptor<RecurringExpenseRule>())
            let nextDue = rules.compactMap { $0.nextOccurrence(after: now) }.min()
            let seconds = min(3_600, max(1, nextDue?.timeIntervalSince(now) ?? 3_600))
            
            scheduleMaintenance(afterNanoseconds: UInt64(seconds * 1_000_000_000))
            
        } catch {
            Self.logger.error(
                "Recurring maintenance failed: \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            scheduleMaintenance(afterNanoseconds: retryDelay)
            retryDelay = min(retryDelay * 2, 300_000_000_000)
        }
    }
}
