//
//  WatchSnapshotReceiver.swift
//  FinanceTracker
//
//  Created by Enzo on 9/10/26.
//

import Foundation
import WatchConnectivity
import WidgetKit

class WatchSnapshotReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchSnapshotReceiver()
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor in
            if let error {
                print("Watch connectivity activation failed: \(error.localizedDescription)")
            }
            if activationState == .activated {
                print("Watch connectivity activated")
                // Restore the last delivered context even if no new transfer arrives.
                if let data = session.receivedApplicationContext["snapshot"] as? Data {
                    applySnapshot(data)
                }
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("Watch received application context")
        guard let data = applicationContext["snapshot"] as? Data else {
            print("Watch context is missing snapshot data")
            return
        }
        Task { @MainActor in
            applySnapshot(data)
        }
    }

    private func applySnapshot(_ data: Data) {
        do {
            let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: data)
            if let current = SnapshotManager.shared.snapshot, current.generatedAt > snapshot.generatedAt { return }
            try WatchSnapshotCache.save(snapshot)
            SnapshotManager.shared.updateSnapshot(to: snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: WatchSnapshotCache.widgetKind)
            print("Watch snapshot applied")
        } catch {
            print("Decoding Watch snapshot failed: \(error.localizedDescription)")
        }
    }
}
