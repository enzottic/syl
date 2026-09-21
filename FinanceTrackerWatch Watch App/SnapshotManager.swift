//
//  SnapshotManager.swift
//  FinanceTracker
//
//  Created by Enzo on 9/10/26.
//
import Foundation

@Observable
class SnapshotManager {
    static let shared = SnapshotManager(snapshot: WatchSnapshotCache.load())
    
    var snapshot: WatchSnapshot? = nil

    init(snapshot: WatchSnapshot? = nil) {
        self.snapshot = snapshot
    }
    
    func updateSnapshot(to snapshot: WatchSnapshot) {
        self.snapshot = snapshot
    }
}
