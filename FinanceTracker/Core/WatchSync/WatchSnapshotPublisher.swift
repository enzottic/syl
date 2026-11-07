import CoreData
import Foundation
import OSLog
import SageKit
import SwiftData

/// Republishes the Watch snapshot whenever the ledger changes, including saves made by Siri and
/// Shortcuts while the app runs in the background without a scene.
@MainActor
final class WatchSnapshotPublisher {
    private static let logger = Logger(subsystem: "me.enzottic.FinanceTracker", category: "WatchSync")

    private let container: ModelContainer
    private let configuration: AppConfiguration
    private let debounce: Duration
    private let isOnboarded: () -> Bool
    private let send: (WatchSnapshot) -> Void
    private var observers: [NSObjectProtocol] = []
    private var pendingPublish: Task<Void, Never>?

    init(
        container: ModelContainer,
        configuration: AppConfiguration,
        debounce: Duration = .milliseconds(250),
        isOnboarded: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: "hasOpenedAppOnce") },
        send: @escaping (WatchSnapshot) -> Void = { WatchSnapshotSender.shared.sendUpdatedMonthlySnapshot(snapshot: $0) }
    ) {
        self.container = container
        self.configuration = configuration
        self.debounce = debounce
        self.isOnboarded = isOnboarded
        self.send = send
    }

    func start() {
        guard observers.isEmpty else { return }

        observers.append(NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self, container] notification in
            guard (notification.object as? ModelContext)?.container === container else { return }
            Task { @MainActor [weak self] in self?.schedulePublish() }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil, event.succeeded else { return }
            Task { @MainActor [weak self] in self?.schedulePublish() }
        })
    }

    func publish() {
        pendingPublish?.cancel()
        pendingPublish = nil
        guard isOnboarded() else { return }

        do {
            guard let snapshot = try WatchSnapshotBuilder.makeSnapshot(
                container: container,
                categoryColors: configuration.categoryColors,
                currencyCode: configuration.ledgerCurrencyCode,
                monthlyBudget: Double(configuration.totalMonthlyIncome)
            ) else { return }
            send(snapshot)
        } catch {
            Self.logger.error("Could not prepare Watch snapshot: \(error.localizedDescription)")
        }
    }

    private func schedulePublish() {
        pendingPublish?.cancel()
        pendingPublish = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            self?.publish()
        }
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        pendingPublish?.cancel()
    }
}
