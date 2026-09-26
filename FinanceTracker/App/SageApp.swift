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
    @State private var didCompleteUITestOnboarding = false
    
    @State private var containerResult: Result<ModelContainer, any Error>?
    @State private var recurringExpenseCoordinator: RecurringExpenseCoordinator?
    @State private var recurringReminders: RecurringReminderCoordinator?
    private let connectivity = WatchSnapshotSender.shared
    
    @MainActor
    init() {
        Self.configureNavigationBarAppearance()

        if UITestConfiguration.isEnabled {
            WhatsNewStore.markCurrentVersionSeen()
        }

        // Keep the store configuration stable across the app, widgets, and App Intents until
        // the next app launch.
        SageModelContainer.activateCloudKitPreference()

        let containerResult: Result<ModelContainer, any Error>?
        if SagePreferences.defaults.bool(forKey: SageModelContainer.pendingCloudDeletionKey) {
            // The Core Data purge must run before SwiftData opens this shared store.
            containerResult = nil
        } else if UITestConfiguration.isEnabled {
            containerResult = Result {
                let container = try SageModelContainer.make(for: .test)
                if let seedName = UITestConfiguration.seedExpenseName {
                    container.mainContext.insert(
                        Expense(name: seedName, amount: 42.50, category: .wants, date: .now)
                    )
                    try container.mainContext.save()
                }
                if UITestConfiguration.seedsSearch {
                    let date = Date.now
                    for index in 0..<101 {
                        container.mainContext.insert(Expense(
                            name: "Search Needle \(index)", amount: 1,
                            date: date.addingTimeInterval(Double(-index))
                        ))
                    }
                    try container.mainContext.save()
                }
                if UITestConfiguration.seedsCalendar {
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: .now)
                    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
                    container.mainContext.insert(Expense(name: "Calendar Coffee", amount: 7.50, date: today))
                    container.mainContext.insert(RecurringExpenseRule(
                        name: "Calendar Subscription", amount: 15, note: "", category: .wants,
                        frequency: .daily, startDate: tomorrow
                    ))
                    container.mainContext.insert(RecurringExpenseRule(
                        name: "Expired Subscription", amount: 999, note: "", category: .wants,
                        frequency: .daily, startDate: today, endDate: today, lastGeneratedDate: today
                    ))
                    try container.mainContext.save()
                }
                return container
            }
        } else {
            containerResult = SageModelContainer.shared.flatMap { container in
                Result {
                    #if DEBUG
                    let context = ModelContext(container)
                    MockDataSeeder.seed(into: context)
                    try context.save()
                    #endif
                    return container
                }
            }
        }
        _containerResult = State(initialValue: containerResult)
        let reminders: RecurringReminderCoordinator?
        if case let .some(.success(container)) = containerResult,
           !UITestConfiguration.isEnabled,
           ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            reminders = RecurringReminderCoordinator(container: container)
        } else {
            reminders = nil
        }
        _recurringReminders = State(initialValue: reminders)

        // Present notifications that fire while the app is foreground
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // Make ExpenseStore resolvable via @Dependency in App Intents.
        if case let .some(.success(container)) = containerResult {
            let expenseStore = ExpenseStore(modelContainer: container)
            AppDependencyManager.shared.add(dependency: expenseStore)
        }

        #if !DEBUG
        let coordinator: RecurringExpenseCoordinator?
        if case let .some(.success(container)) = containerResult {
            coordinator = RecurringExpenseCoordinator(
                modelContainer: container,
                cloudKitEnabled: SageModelContainer.isCloudKitEnabled
            )
        } else {
            coordinator = nil
        }
        #else
        let coordinator: RecurringExpenseCoordinator? = nil
        #endif
        _recurringExpenseCoordinator = State(initialValue: coordinator)
        coordinator?.start()

        // Refresh dynamic shortcut parameter values after registering dependencies.
        // App Shortcut phrases are extracted at build time and discovered by the system.
        if containerResult != nil {
            SageShortcutsProvider.updateAppShortcutParameters()
        }

    }
    
    var body: some Scene {
        WindowGroup {
            if appConfiguration.isWaitingForDeletionRestart {
                PendingDeletionRestartView()
            } else {
                switch containerResult {
                case nil:
                    PendingDeletionRecoveryView(finish: finishPendingDeletion)
                case let .some(.success(container)):
                    mainContent
                        .modifier(RelativeDateRefreshModifier())
                        .modelContainer(container)
                case let .some(.failure(error)):
                    DataStoreRecoveryView(error: error)
                }
            }
        }
        .environment(appConfiguration)
        .environment(\.recurringReminders, recurringReminders)
        .environment(\.categoryColors, appConfiguration.categoryColors)
        .onChange(of: appConfiguration.isWaitingForDeletionRestart) { _, waiting in
            if waiting { recurringExpenseCoordinator?.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active || phase == .background else { return }
            publishMonthlySnapshot()
        }
    }
    
    private func publishMonthlySnapshot() {
        guard !UITestConfiguration.isEnabled,
              ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              hasOpenedAppOnce,
              case let .some(.success(container)) = containerResult else {
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

    @MainActor
    private func finishPendingDeletion() async -> Bool {
        do {
            try DataDeletionService.deleteLocalExport()
        } catch {
            return false
        }
        let preferencesQueued = appConfiguration.resetAllSettings()
        guard await appConfiguration.finishCloudDeletion(preferencesQueued: preferencesQueued) else {
            return false
        }
        UserDefaults.standard.removeObject(forKey: "hasOpenedAppOnce")
        let result = SageModelContainer.shared
        if case let .success(container) = result {
            if let snapshot = try? WatchSnapshotBuilder.makeSnapshot(
                container: container,
                categoryColors: appConfiguration.categoryColors,
                currencyCode: appConfiguration.ledgerCurrencyCode,
                monthlyBudget: 0
            ) {
                connectivity.sendUpdatedMonthlySnapshot(snapshot: snapshot)
            }
            let expenseStore = ExpenseStore(modelContainer: container)
            AppDependencyManager.shared.add(dependency: expenseStore)
            recurringReminders = RecurringReminderCoordinator(container: container)
            #if !DEBUG
            let coordinator = RecurringExpenseCoordinator(modelContainer: container, cloudKitEnabled: false)
            recurringExpenseCoordinator = coordinator
            coordinator.start()
            #endif
            SageShortcutsProvider.updateAppShortcutParameters()
        }
        containerResult = result
        return true
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if UITestConfiguration.isEnabled {
                if UITestConfiguration.showsOnboarding, !didCompleteUITestOnboarding {
                    OnboardingView {
                        didCompleteUITestOnboarding = true
                    }
                } else {
                    RootTabView()
                }
            } else if !hasOpenedAppOnce {
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
            if !UITestConfiguration.isEnabled,
               !hasOpenedAppOnce,
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

private struct PendingDeletionRestartView: View {
    var body: some View {
        ContentUnavailableView(
            "Deletion continues on next launch",
            systemImage: "icloud",
            description: Text("Syl removed the data on this iPhone. Close Syl from the App Switcher, then reopen it while connected to iCloud to finish deleting the iCloud copy. Sync stays off until deletion succeeds.")
        )
    }
}

private struct PendingDeletionRecoveryView: View {
    let finish: () async -> Bool
    @State private var isRunning = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 16) {
            if isRunning {
                ProgressView("Finishing iCloud deletion")
            } else {
                ContentUnavailableView(
                    "iCloud deletion pending",
                    systemImage: "icloud.slash",
                    description: Text("Connect to iCloud to finish deleting Syl data. Sync remains off until this succeeds.")
                )
                Button("Retry iCloud Deletion") {
                    Task { await attempt() }
                }
                .buttonStyle(.borderedProminent)
            }
            if failed {
                Text("Syl could not finish iCloud deletion. Check your connection and iCloud account, then retry.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .task { await attempt() }
    }

    @MainActor
    private func attempt() async {
        guard !isRunning else { return }
        isRunning = true
        failed = !(await finish())
        isRunning = false
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
