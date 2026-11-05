//
//  WatchSnapshotSender.swift
//  FinanceTracker
//
//  Created by Enzo on 9/10/26.
//

import Foundation
import OSLog
import SageKit
import WatchConnectivity

class WatchSnapshotSender: NSObject, WCSessionDelegate {
    private nonisolated static let logger = Logger(subsystem: "me.enzottic.FinanceTracker", category: "WatchSync")
    static let shared = WatchSnapshotSender()
    private var pendingPayload: [String: Any]?
    
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
                Self.logger.debug("WatchConnectivity activated; Watch app installed: \(session.isWatchAppInstalled)")
                if let pendingPayload {
                    setContext(to: pendingPayload)
                }
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    
    func setContext(to payload: [String: Any]) {
        pendingPayload = payload
        let session = WCSession.default
        if session.activationState == .activated {
            do {
                try session.updateApplicationContext(payload)
                pendingPayload = nil
                Self.logger.debug("Watch snapshot submitted for background delivery")
            } catch {
                Self.logger.error("Updating Watch context failed: \(error.localizedDescription)")
            }
        } else {
            Self.logger.debug("Watch snapshot pending session activation")
        }
    }
    
    func sendUpdatedMonthlySnapshot(snapshot: WatchSnapshot) {
        do {
            let snapshotData = try JSONEncoder().encode(snapshot)
            let payload: [String:Any] = [WatchSnapshot.applicationContextKey: snapshotData]
            setContext(to: payload)
        } catch {
            Self.logger.error("Encoding Watch snapshot failed: \(error.localizedDescription)")
        }
    }
}
