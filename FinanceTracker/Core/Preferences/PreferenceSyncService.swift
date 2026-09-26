import Foundation
import SageKit

nonisolated protocol CloudPreferenceStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudPreferenceStore {}

// Responsible for syncing preferences to the iCloud KVS. Listens to events for updates
@MainActor
final class PreferenceSyncService {
    enum Key: String, CaseIterable, Sendable {
        case appearance, totalMonthlyIncome, needsPercent, wantsPercent, savingsPercent
        case smartTaggingMode, hasCompletedSetup, ledgerCurrency

        var storageKey: String {
            self == .ledgerCurrency ? LedgerCurrency.storageKey : rawValue
        }

        static let allocation: Set<Key> = [.needsPercent, .wantsPercent, .savingsPercent]
    }

    struct Snapshot {
        let keys: Set<Key>
        private let values: [Key: Any]

        fileprivate init(keys: Set<Key>, values: [Key: Any]) {
            self.keys = keys
            self.values = values
        }

        subscript(key: Key) -> Any? { values[key] }
    }

    enum Status: Equatable {
        case stopped, running, synchronizationUnavailable, quotaExceeded, accountChanged
    }

    var onChange: ((Snapshot) -> Void)?
    var onStatusChange: ((Status) -> Void)?
    private(set) var status: Status = .stopped {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    private let hasConsent: () -> Bool
    private let makeStore: () -> any CloudPreferenceStore
    private let notificationCenter: NotificationCenter
    private var store: (any CloudPreferenceStore)?
    private var observer: NSObjectProtocol?
    private var generation: UInt64 = 0

    init(
        hasConsent: @escaping () -> Bool,
        makeStore: (() -> any CloudPreferenceStore)? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.hasConsent = hasConsent
        self.makeStore = makeStore ?? { NSUbiquitousKeyValueStore.default }
        self.notificationCenter = notificationCenter
    }

    deinit {
        if let observer { notificationCenter.removeObserver(observer) }
    }

    private var activeStore: (any CloudPreferenceStore)? {
        guard hasConsent() else {
            if store != nil { stop() }
            return nil
        }
        return store
    }

    // Explicit start/re-enable. A successful synchronize is not server confirmation.
    func start() {
        guard hasConsent() else { stop(); return }
        guard store == nil else { return }
        
        generation &+= 1
        let currentGeneration = generation
        let acquired = makeStore()
        store = acquired
        
        observer = notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: acquired,
            queue: nil
        ) { [weak self] notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.receive(reason: reason, changedKeys: keys)
            }
        }
        
        status = acquired.synchronize() ? .running : .synchronizationUnavailable
        read(Set(Key.allCases))
    }

    func stop() {
        generation &+= 1
        if let observer { notificationCenter.removeObserver(observer) }
        observer = nil
        store = nil
        status = .stopped
    }

    func recheck() {
        guard let store = activeStore else { return }
        
        let synchronized = store.synchronize()
        if status != .quotaExceeded {
            status = synchronized ? .running : .synchronizationUnavailable
        }
        
        read(Set(Key.allCases))
    }

    private func receive(reason: Int?, changedKeys: [String]?) {
        guard activeStore != nil else { return }
        
        switch reason {
        case NSUbiquitousKeyValueStoreAccountChange:
            stop()
            status = .accountChanged
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            status = .quotaExceeded
        case NSUbiquitousKeyValueStoreInitialSyncChange, NSUbiquitousKeyValueStoreServerChange:
            status = .running
            let keys = changedKeys.map { names in
                Set(Key.allCases.filter { names.contains($0.storageKey) })
            } ?? Set(Key.allCases)
            read(keys)
        default:
            break
        }
    }

    @discardableResult
    private func read(_ changedKeys: Set<Key>) -> Snapshot? {
        guard !changedKeys.isEmpty, let store = activeStore else { return nil }
        
        var keys = changedKeys
        
        // Allocation is one coherent value, even though its existing KVS format is three keys.
        if !keys.isDisjoint(with: Key.allocation) { keys.formUnion(Key.allocation) }
        
        var values: [Key: Any] = [:]
        for key in keys {
            values[key] = store.object(forKey: key.storageKey)
        }
        
        let snapshot = Snapshot(keys: keys, values: values)
        onChange?(snapshot)
        return snapshot
    }

    // Validation belongs to the configuration; transport only requires consent and available quota.
    func publish(_ values: [Key: Any]) {
        guard let store = activeStore, status != .quotaExceeded else { return }
        for (key, value) in values { store.set(value, forKey: key.storageKey) }
    }

    func markSetupComplete() {
        publish([.hasCompletedSetup: true])
    }

    // Delete All Data explicitly authorizes clearing these keys even when ordinary sync is off.
    // synchronize() only queues the change; it is not a server acknowledgement.
    @discardableResult
    func resetForDataDeletion() -> Bool {
        let deletionStore = store ?? makeStore()
        for key in Key.allCases { deletionStore.removeObject(forKey: key.storageKey) }
        return deletionStore.synchronize()
    }
}
