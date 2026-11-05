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
import OSLog

@main
struct SageApp: App {
    private static let logger = Logger(subsystem: "me.enzottic.FinanceTracker", category: "WatchSync")
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
        switch containerResult {
        case let .success(container):
            let expenseStore = ExpenseStore(modelContainer: container)
            AppDependencyManager.shared.add(dependency: expenseStore)
        case .failure:
            if let unavailableStore = try? ExpenseStore.unavailable() {
                AppDependencyManager.shared.add(dependency: unavailableStore)
            }
        }

        // Unit tests are hosted in the app and shouldn't index the simulator's real store.
        let environment = ProcessInfo.processInfo.environment
        if case .success = containerResult,
           environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
           environment["XCTestConfigurationFilePath"] == nil {
            ExpenseSpotlightIndexer.shared?.start()
        }

        #if !DEBUG
        if case let .success(container) = containerResult {
            recurringExpenseCoordinator = RecurringExpenseCoordinator(
                modelContainer: container,
                cloudKitEnabled: SageModelContainer.supportsCloudSync && !SageModelContainer.isRunningWithoutCloudSync
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
            if phase == .active {
                appConfiguration.recheckPreferences()
                ExpenseSpotlightIndexer.shared?.scheduleUpdate()
            }
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
            Self.logger.error("Could not prepare Watch snapshot: \(error.localizedDescription)")
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
        
        let largeTitleFont = UIFont(name: "MomoTrustDisplay-Regular", size: 34) ?? .systemFont(ofSize: 34, weight: .bold)
        appearance.largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: largeTitleFont)
        ]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

private struct DataStoreRecoveryView: View {
    let error: any Swift.Error

    @Environment(\.openURL) private var openURL
    @State private var hasPausedCloudSync = false

    private var fallbackAlsoFailed: Bool {
        if case .unavailableWithoutCloudSync = error as? SageModelContainer.Error { return true }
        return false
    }

    private var canPauseCloudSync: Bool { SageModelContainer.supportsCloudSync && !fallbackAlsoFailed }

    private var errorCode: String {
        var error = error as NSError
        if case let .unavailableWithoutCloudSync(underlying) = self.error as? SageModelContainer.Error {
            error = underlying
        }
        return "\(error.domain) \(error.code)"
    }

    private var supportURL: URL? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "contact@getsyl.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Syl can't open its data"),
            URLQueryItem(name: "body", value: "\n\n\n--- Please do not remove the info below ---\nSyl \(version) · iOS \(UIDevice.current.systemVersion) · \(errorCode)")
        ]
        return components.url
    }

    var body: some View {
        ContentUnavailableView {
            Label("Your data could not open", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: 12) {
                if hasPausedCloudSync {
                    Text("Close Syl from the App Switcher and open it again. Syl will open your data without iCloud sync, and try iCloud again each time it opens.")
                } else if fallbackAlsoFailed {
                    Text("Syl couldn't open your data, even without iCloud sync. Contact support so we can help you get it back.")
                } else {
                    Text("Check that your device has free storage, then close Syl and open it again.")
                }
                Text("Don't delete Syl. Deleting the app removes data that hasn't synced to iCloud.")
                    .fontWeight(.semibold)
                Text("Error: \(errorCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } actions: {
            if canPauseCloudSync && !hasPausedCloudSync {
                Button("Open Without iCloud Sync") {
                    SageModelContainer.isCloudSyncPaused = true
                    hasPausedCloudSync = true
                }
                .buttonStyle(.borderedProminent)
            }
            if let supportURL {
                Button("Contact Support") { openURL(supportURL) }
            }
        }
    }
}

struct MainAppPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [SageKitPackage.self]
    }
}
