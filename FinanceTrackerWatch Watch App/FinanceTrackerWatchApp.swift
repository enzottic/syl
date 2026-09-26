//
//  FinanceTrackerWatchApp.swift
//  FinanceTrackerWatch Watch App
//
//  Created by Enzo on 9/10/26.
//

import SwiftUI

@main
struct FinanceTrackerWatch_Watch_AppApp: App {
    @State private var snapshotManager = SnapshotManager.shared
    private let connectivity = WatchSnapshotReceiver.shared

    init() {
        #if DEBUG
        // Opt-in fixture for simulator layout checks; never used in device builds.
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-watch-preview") {
            SnapshotManager.shared.updateSnapshot(to: .preview)
        }
        #endif
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            SageDashboardView()
                .environment(snapshotManager)
        }
    }
}
