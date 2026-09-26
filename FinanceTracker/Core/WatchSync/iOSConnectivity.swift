//
//  iOSConnectivity.swift
//  FinanceTracker
//
//  Created by Enzo on 9/10/26.
//

import Foundation
import SageKit
import WatchConnectivity

class iOSConnectivity: NSObject, WCSessionDelegate {
    static let shared = iOSConnectivity()
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
                print("iPhone WatchConnectivity activation failed: \(error.localizedDescription)")
            }
            if activationState == .activated {
                print("iPhone WatchConnectivity activated; Watch app installed: \(session.isWatchAppInstalled)")
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
                print("Watch snapshot submitted for background delivery")
            } catch {
                print("Updating Watch context failed: \(error.localizedDescription)")
            }
        } else {
            print("Watch snapshot pending session activation")
        }
    }
    
    func sendUpdatedMonthlySnapshot(snapshot: WatchSnapshot) {
        do {
            let snapshotData = try JSONEncoder().encode(snapshot)
            let payload: [String:Any] = ["snapshot": snapshotData]
            setContext(to: payload)
        } catch {
            print("Encoding Watch snapshot failed: \(error.localizedDescription)")
        }
    }
}
