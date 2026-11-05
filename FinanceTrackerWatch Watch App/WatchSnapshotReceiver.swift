//
//  WatchSnapshotReceiver.swift
//  FinanceTracker
//
//  Created by Enzo on 9/10/26.
//

import Foundation
import OSLog
import WatchConnectivity
import WidgetKit

class WatchSnapshotReceiver: NSObject, WCSessionDelegate {
    private nonisolated static let logger = Logger(subsystem: "me.enzottic.FinanceTracker", category: "WatchSync")
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
                Self.logger.error("WatchConnectivity activation failed: \(error.localizedDescription)")
            }
            if activationState == .activated {
                Self.logger.debug("WatchConnectivity activated")
                // Restore the last delivered context even if no new transfer arrives.
                if let data = session.receivedApplicationContext[WatchSnapshot.applicationContextKey] as? Data {
                    applySnapshot(data)
                }
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Self.logger.debug("Received application context")
        guard let data = applicationContext[WatchSnapshot.applicationContextKey] as? Data else {
            Self.logger.error("Application context is missing snapshot data")
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
            Self.logger.debug("Watch snapshot applied")
        } catch {
            Self.logger.error("Decoding Watch snapshot failed: \(error.localizedDescription)")
        }
    }
}
