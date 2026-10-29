//
//  SageApp.swift
//  FinanceTracker
//
//  Created by Enzo on 9/21/25.
//

import SwiftUI
import SwiftData
import AppIntents
import SageKit
import UserNotifications

@main
struct SageApp: App {
    @AppStorage("hasOpenedAppOnce") var hasOpenedAppOnce: Bool = false
    @Environment(\.scenePhase) var scenePhase
    
    @State private var appConfiguration = AppConfiguration()
    
    private let containerResult: Result<ModelContainer, any Error>
    private let recurringExpenseCoordinator: RecurringExpenseCoordinator?
    private let recurringReminders: RecurringReminderCoordinator?
    private let connectivity = WatchSnapshotSender.shared
    
    @MainActor
    init() {
        Self.configureNavigationBarAppearance()

        let containerResult = SageModelContainer.shared.flatMap { container in
            Result {
                #if DEBUG
                let context = ModelContext(container)
                MockDataSeeder.seed(into: context)
                try context.save()
                #endif
                return container
            }
        }
        self.containerResult = containerResult
        if case let .success(container) = containerResult,
           ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            recurringReminders = RecurringReminderCoordinator(container: container)
        } else {
            recurringReminders = nil
        }

        // Present notifications that fire while the app is foreground
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // Make ExpenseStore resolvable via @Dependency in App Intents.
        if case let .success(container) = containerResult {
            let expenseStore = ExpenseStore(modelContainer: container)
            AppDependencyManager.shared.add(dependency: expenseStore)
        }

        #if !DEBUG
        if case let .success(container) = containerResult {
            recurringExpenseCoordinator = RecurringExpenseCoordinator(
                modelContainer: container,
                cloudKitEnabled: SageModelContainer.supportsCloudSync
            )
        } else {
            recurringExpenseCoordinator = nil
        }
        #else
        recurringExpenseCoordinator = nil
        #endif

        recurringExpenseCoordinator?.start()

        // Refresh dynamic shortcut parameter values after registering dependencies.
        // App Shortcut phrases are extracted at build time and discovered by the system.
        SageShortcutsProvider.updateAppShortcutParameters()

    }
    
    var body: some Scene {
        WindowGroup {
            switch containerResult {
            case let .success(container):
                mainContent
                    .modifier(RelativeDateRefreshModifier())
                    .modelContainer(container)
            case let .failure(error):
                DataStoreRecoveryView(error: error)
            }
        }
        .environment(appConfiguration)
        .environment(\.recurringReminders, recurringReminders)
        .environment(\.categoryColors, appConfiguration.categoryColors)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active || phase == .background else { return }
            if phase == .active { appConfiguration.recheckPreferences() }
            publishMonthlySnapshot()
        }
    }
    
    private func publishMonthlySnapshot() {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              hasOpenedAppOnce,
              case let .success(container) = containerResult else {
            return
        }
        
        do {
            guard let snapshot = try WatchSnapshotBuilder.makeSnapshot(
                container: container,
                categoryColors: appConfiguration.categoryColors,
                currencyCode: appConfiguration.ledgerCurrencyCode,
                monthlyBudget: Double(appConfiguration.totalMonthlyIncome)
            ) else {
                return
            }
            
            connectivity.sendUpdatedMonthlySnapshot(snapshot: snapshot)
            
        } catch {
            print("Could not prepare watch snapshot: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if !hasOpenedAppOnce {
                OnboardingView()
            } else {
                RootTabView()
            }
        }
        .textCase(nil)
        .fontDesign(.rounded)
        .preferredColorScheme(appConfiguration.selectedAppearance.colorScheme)
        .task {
            recurringReminders?.start(configuration: appConfiguration)
            // Local notifications deliver while suspended; this only replenishes the horizon.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3_600)) } catch { return }
                recurringReminders?.refresh()
            }
        }
        .onChange(of: appConfiguration.billRemindersEnabled) { recurringReminders?.refresh() }
        .onChange(of: appConfiguration.billReminderDaysBefore) { recurringReminders?.refresh() }
        .onChange(of: appConfiguration.billReminderTimeMinutes) { recurringReminders?.refresh() }
        .onChange(of: appConfiguration.dailyExpenseReminderEnabled) { recurringReminders?.refresh() }
        .onChange(of: appConfiguration.dailyExpenseReminderTimeMinutes) { recurringReminders?.refresh() }
        .onChange(of: appConfiguration.hideBillReminderDetails) { recurringReminders?.refresh() }
        .onChange(of: appConfiguration.ledgerCurrencyCode) { recurringReminders?.refresh() }
        .onChange(of: appConfiguration.hasCompletedSetupOnAnotherDevice, initial: true) { _, completed in
            if !hasOpenedAppOnce,
               completed {
                WhatsNewStore.markCurrentVersionSeen()
                hasOpenedAppOnce = true
            }
        }
    }
    
    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        
        appearance.largeTitleTextAttributes = [
            .font: UIFont(name: "MomoTrustDisplay-Regular", size: 34) ?? UIFont.systemFont(ofSize: 34)
        ]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

private struct DataStoreRecoveryView: View {
    let error: any Swift.Error

    var body: some View {
        ContentUnavailableView(
            "Your data could not open",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text("Syl could not access its shared storage. Check available device storage, then close and reopen the app. \(error.localizedDescription)")
        )
    }
}

struct MainAppPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [SageKitPackage.self]
    }
}
