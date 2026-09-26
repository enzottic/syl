import Foundation
import Testing
@testable import SageKit

@Suite("Preference sync service", .serialized)
@MainActor
struct PreferenceSyncServiceTests {
    private typealias Key = PreferenceSyncService.Key

    @Test
    func offNeverAcquiresOrAccessesCloudIncludingCachedStore() async {
        let fixture = Fixture()
        fixture.cloud.values = ["isCloudSyncEnabled": true]
        fixture.service.start()
        fixture.exerciseOutbound()
        fixture.service.recheck()
        fixture.service.reset()
        fixture.post(reason: NSUbiquitousKeyValueStoreServerChange)
        await drainNotifications()
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.snapshots.isEmpty)

        fixture.consent = true
        fixture.service.start()
        fixture.consent = false // The authoritative persisted consent can change externally.
        fixture.cloud.operations.removeAll()
        fixture.snapshots.removeAll()
        fixture.exerciseOutbound()
        fixture.service.recheck()
        fixture.service.reset()
        fixture.post(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        await drainNotifications()
        #expect(fixture.acquisitions == 1)
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.snapshots.isEmpty)
        #expect(fixture.service.status == .stopped)
    }

    @Test
    func startReadsExistingValuesWithoutEchoOrConsentKeyAndSubscribesFirst() async throws {
        let fixture = Fixture(enabled: true)
        fixture.cloud.values = ["appearance": "Dark", "isCloudSyncEnabled": false]
        fixture.cloud.onSynchronize = { [weak fixture] in
            fixture?.post(reason: NSUbiquitousKeyValueStoreInitialSyncChange, keys: ["appearance"])
        }
        fixture.service.start()
        #expect(fixture.acquisitions == 1)
        #expect(fixture.cloud.operations.first == .synchronize)
        #expect(fixture.snapshots.count == 1)
        #expect(fixture.snapshots[0][.appearance] as? String == "Dark")
        #expect(fixture.snapshots[0].keys == Set(Key.allCases))
        await drainNotifications()
        #expect(fixture.snapshots.count == 2) // Includes the event emitted during synchronize.
        #expect(fixture.snapshots[1].keys == [.appearance])
        #expect(!fixture.cloud.operations.contains(.read("isCloudSyncEnabled")))
        #expect(!fixture.cloud.operations.contains { if case .write = $0 { return true }; return false })
        let operations = fixture.cloud.operations
        fixture.service.start()
        #expect(fixture.cloud.operations == operations)
    }

    @Test
    func localChangesPublishWithoutSynchronizingAndNeverBulkUpload() {
        let fixture = Fixture(enabled: true)
        fixture.service.start()
        fixture.cloud.operations.removeAll()
        fixture.exerciseOutbound()
        #expect(fixture.cloud.values["appearance"] as? String == "Light")
        #expect(fixture.cloud.values["totalMonthlyIncome"] as? Int == 2500)
        #expect(fixture.cloud.values["hasCompletedSetup"] as? Bool == true)
        #expect(!fixture.cloud.operations.contains(.synchronize))
        #expect(fixture.cloud.values[Key.ledgerCurrency.storageKey] as? String == "USD")
        #expect(!fixture.cloud.operations.contains { if case .read = $0 { return true }; return false })
        #expect(!fixture.cloud.operations.contains(.write("isCloudSyncEnabled")))
    }

    @Test(arguments: [NSUbiquitousKeyValueStoreInitialSyncChange, NSUbiquitousKeyValueStoreServerChange])
    func notificationsHonorChangedKeysAndReadCoherentAllocation(reason: Int) async {
        let fixture = Fixture(enabled: true)
        fixture.service.start()
        fixture.cloud.operations.removeAll()
        fixture.snapshots.removeAll()
        fixture.cloud.values = ["appearance": "Dark", "needsPercent": 0.6, "wantsPercent": 0.2,
                                "savingsPercent": 0.2, Key.ledgerCurrency.storageKey: "USD"]
        fixture.post(reason: reason, keys: ["appearance", "isCloudSyncEnabled"])
        await drainNotifications()
        #expect(fixture.cloud.operations == [.read("appearance")])
        #expect(fixture.snapshots.last?.keys == [.appearance])
        fixture.cloud.operations.removeAll()
        fixture.post(reason: reason, keys: ["needsPercent"])
        await drainNotifications()
        #expect(fixture.snapshots.last?.keys == Key.allocation)
        #expect(Set(fixture.cloud.operations) == Set(Key.allocation.map { .read($0.storageKey) }))
        #expect(fixture.snapshots.last?[.wantsPercent] as? Double == 0.2)
        fixture.post(reason: reason, keys: [Key.ledgerCurrency.storageKey])
        await drainNotifications()
        #expect(fixture.snapshots.last?.keys == [.ledgerCurrency])
        fixture.cloud.operations.removeAll()
        fixture.post(reason: reason, keys: [])
        fixture.post(reason: reason, keys: ["unrelated"])
        await drainNotifications()
        #expect(fixture.cloud.operations.isEmpty)
    }

    @Test
    func missingChangedKeysReadsAllButMalformedReasonDoesNothing() async {
        let fixture = Fixture(enabled: true)
        fixture.service.start()
        fixture.snapshots.removeAll()
        fixture.cloud.operations.removeAll()
        fixture.post(reason: nil)
        fixture.post(reason: 999, keys: ["appearance"])
        await drainNotifications()
        #expect(fixture.cloud.operations.isEmpty)
        fixture.post(reason: NSUbiquitousKeyValueStoreServerChange)
        await drainNotifications()
        #expect(fixture.snapshots.last?.keys == Set(Key.allCases))
    }

    @Test
    func queuedEventsCannotCrossStopAndReenable() async {
        let fixture = Fixture(enabled: true)
        fixture.service.start()
        fixture.post(reason: NSUbiquitousKeyValueStoreServerChange, keys: ["appearance"])
        fixture.post(reason: NSUbiquitousKeyValueStoreAccountChange)
        fixture.service.stop()
        fixture.service.start()
        fixture.cloud.operations.removeAll()
        fixture.snapshots.removeAll()
        await drainNotifications()
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.snapshots.isEmpty)
        #expect(fixture.service.status == .running)
        fixture.post(reason: NSUbiquitousKeyValueStoreServerChange, keys: ["appearance"])
        await drainNotifications()
        #expect(fixture.snapshots.count == 1)
        fixture.service.stop()
        fixture.cloud.operations.removeAll()
        fixture.post(reason: NSUbiquitousKeyValueStoreServerChange)
        fixture.exerciseOutbound()
        fixture.service.reset()
        await drainNotifications()
        #expect(fixture.cloud.operations.isEmpty)
    }

    @Test
    func quotaBlocksUploadsWithoutApplyingRemoteAndServerEventRecovers() async {
        let fixture = Fixture(enabled: true)
        fixture.service.start()
        fixture.snapshots.removeAll()
        fixture.cloud.operations.removeAll()
        fixture.post(reason: NSUbiquitousKeyValueStoreQuotaViolationChange, keys: ["appearance"])
        await drainNotifications()
        #expect(fixture.service.status == .quotaExceeded)
        fixture.exerciseOutbound()
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.snapshots.isEmpty)
        fixture.service.recheck()
        #expect(fixture.service.status == .quotaExceeded)
        fixture.post(reason: NSUbiquitousKeyValueStoreServerChange, keys: ["appearance"])
        await drainNotifications()
        #expect(fixture.service.status == .running)
        fixture.service.markSetupComplete()
        #expect(fixture.cloud.operations.contains(.write("hasCompletedSetup")))
    }

    @Test
    func accountChangeStopsUntilExplicitStartWithoutUploadingOldPreferences() async {
        let fixture = Fixture(enabled: true)
        fixture.service.start()
        fixture.cloud.operations.removeAll()
        fixture.snapshots.removeAll()
        fixture.post(reason: NSUbiquitousKeyValueStoreAccountChange)
        fixture.post(reason: NSUbiquitousKeyValueStoreServerChange)
        await drainNotifications()
        #expect(fixture.service.status == .accountChanged)
        #expect(fixture.statuses.last == .accountChanged)
        fixture.exerciseOutbound()
        fixture.service.recheck()
        fixture.service.reset()
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.snapshots.isEmpty)
        fixture.cloud.values["appearance"] = "Dark"
        fixture.service.start()
        #expect(fixture.snapshots.last?[.appearance] as? String == "Dark")
        #expect(!fixture.cloud.operations.contains { if case .write = $0 { return true }; return false })
    }

    @Test
    func synchronizationFailureIsNotConsentFailureOrServerConfirmation() {
        let fixture = Fixture(enabled: true)
        fixture.cloud.synchronizationResult = false
        fixture.service.start()
        #expect(fixture.service.status == .synchronizationUnavailable)
        #expect(fixture.consent)
        #expect(fixture.snapshots.count == 1)
        fixture.service.markSetupComplete()
        #expect(fixture.cloud.operations.contains(.write("hasCompletedSetup")))
    }

    @Test
    func currencyPublishesWithoutReadingOrDeliveringARemoteSnapshot() {
        let fixture = Fixture(enabled: true)
        fixture.service.start()
        fixture.cloud.operations.removeAll()
        fixture.snapshots.removeAll()
        fixture.service.publish([.ledgerCurrency: "USD"])
        #expect(fixture.cloud.values[Key.ledgerCurrency.storageKey] as? String == "USD")
        #expect(fixture.snapshots.isEmpty)
        #expect(fixture.cloud.operations == [.write(Key.ledgerCurrency.storageKey)])
    }

    @Test(arguments: ["EUR", "USD", "invalid", ""])
    func existingCurrencyCanBeReplaced(remote: String) {
        let fixture = Fixture(enabled: true)
        fixture.cloud.values[Key.ledgerCurrency.storageKey] = remote
        fixture.service.start()
        fixture.cloud.operations.removeAll()
        fixture.service.publish([.ledgerCurrency: "JPY"])
        #expect(fixture.cloud.operations == [.write(Key.ledgerCurrency.storageKey)])
        #expect(fixture.cloud.values[Key.ledgerCurrency.storageKey] as? String == "JPY")
    }

    @Test
    func incomePublishesIndependentlyOfCurrency() {
        let fixture = Fixture(enabled: true)
        fixture.service.start()
        for remote in [nil, "EUR", "invalid", "USD"] as [String?] {
            fixture.cloud.values[Key.ledgerCurrency.storageKey] = remote
            fixture.cloud.operations.removeAll()
            fixture.service.publish([.totalMonthlyIncome: 100, .appearance: "Dark"])
            #expect(Set(fixture.cloud.operations) == [.write("totalMonthlyIncome"), .write("appearance")])
            #expect(fixture.cloud.values["totalMonthlyIncome"] as? Int == 100)
            #expect(fixture.cloud.values[Key.ledgerCurrency.storageKey] as? String == remote)
        }
    }

    @Test
    func resetRemovesOnlyExistingPreferenceKeysWhileConsentStillEnabled() {
        let fixture = Fixture(enabled: true)
        fixture.service.start()
        fixture.cloud.operations.removeAll()
        fixture.service.reset()
        #expect(fixture.consent)
        #expect(Set(fixture.cloud.operations) == Set(Key.allCases.map { .remove($0.storageKey) } + [.synchronize]))
        #expect(fixture.cloud.operations.last == .synchronize)
        fixture.consent = false
        fixture.service.stop()
        fixture.cloud.operations.removeAll()
        fixture.service.reset()
        #expect(fixture.cloud.operations.isEmpty)
    }

    private func drainNotifications() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor
    private final class Fixture {
        let cloud = CloudSpy()
        let notifications = NotificationCenter()
        var consent: Bool
        var acquisitions = 0
        var snapshots: [PreferenceSyncService.Snapshot] = []
        var statuses: [PreferenceSyncService.Status] = []
        lazy var service: PreferenceSyncService = {
            let service = PreferenceSyncService(hasConsent: { [unowned self] in consent }, makeStore: { [unowned self] in
                acquisitions += 1
                return cloud
            }, notificationCenter: notifications)
            service.onChange = { [weak self] in self?.snapshots.append($0) }
            service.onStatusChange = { [weak self] in self?.statuses.append($0) }
            return service
        }()

        init(enabled: Bool = false) { consent = enabled }

        func post(reason: Int?, keys: [String]? = nil) {
            var info: [String: Any] = [:]
            info[NSUbiquitousKeyValueStoreChangeReasonKey] = reason
            info[NSUbiquitousKeyValueStoreChangedKeysKey] = keys
            notifications.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, userInfo: info)
        }

        func exerciseOutbound() {
            service.publish([.appearance: "Light", .totalMonthlyIncome: 2500, .ledgerCurrency: "USD"])
            service.markSetupComplete()
        }
    }

    private final class CloudSpy: NSObject, CloudPreferenceStore {
        enum Operation: Hashable {
            case read(String), write(String), remove(String), synchronize
        }
        var values: [String: Any] = [:]
        var operations: [Operation] = []
        var synchronizationResult = true
        var onSynchronize: (() -> Void)?

        func object(forKey key: String) -> Any? {
            operations.append(.read(key))
            return values[key]
        }
        func set(_ value: Any?, forKey key: String) {
            operations.append(.write(key))
            values[key] = value
        }
        func removeObject(forKey key: String) {
            operations.append(.remove(key))
            values.removeValue(forKey: key)
        }
        func synchronize() -> Bool {
            operations.append(.synchronize)
            onSynchronize?()
            return synchronizationResult
        }
    }
}
