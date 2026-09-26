//
//  SettingsView.swift
//  FinanceTracker
//
//  Created by Enzo on 5/18/26.
//
import SwiftUI
import SwiftData
import WidgetKit
import Darwin
import SageKit

struct SettingsView: View {
    @Environment(AppConfiguration.self) private var config: AppConfiguration
    @Environment(AppRouter.self) private var router: AppRouter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.recurringReminders) private var reminders

    @State private var showExpenseDeletionOptions = false
    @State private var showFullResetConfirmation = false
    @State private var activeDataOperation: DataOperation?

    private var isChangingData: Bool { activeDataOperation != nil }

    private var feedbackURL: URL? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let ios = UIDevice.current.systemVersion
        let body = "\n\n\n--- Please do not remove the info below ---\nSyl \(version) (\(build)) · iOS \(ios) · \(Self.deviceModel)"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "contact@getsyl.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Syl Feedback"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    private static var deviceModel: String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
        #endif
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.settingsPath) {
            List {
                Section {
                    let page = SettingsPage.appearance
                    NavigationLink(value: page) {
                        SettingsListItem(text: page.rawValue, icon: page.icon, color: page.color)
                    }
                }

                Section {
                    ForEach([SettingsPage.budget, .recurringExpenses, .notifications, .tags], id: \.self) { page in
                        NavigationLink(value: page) {
                            SettingsListItem(text: page.rawValue, icon: page.icon, color: page.color)
                        }
                    }
                }

                Section {
                    let page = SettingsPage.backup
                    NavigationLink(value: page) {
                        SettingsListItem(text: page.rawValue, icon: page.icon, color: page.color)
                    }
                }

                Section {
                    if let feedbackURL {
                        Link(destination: feedbackURL) {
                            SettingsListItem(text: "Feedback", icon: "envelope.fill", color: .yellow)
                        }
                        .tint(.primary)
                    } else {
                        SettingsListItem(text: "Feedback unavailable", icon: "envelope.fill", color: .gray)
                    }
                    let page = SettingsPage.privacy
                    NavigationLink(value: page) {
                        SettingsListItem(text: page.rawValue, icon: page.icon, color: page.color)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showExpenseDeletionOptions = true
                    } label: {
                        SettingsListItem(text: "Delete Expense Data", icon: "trash.fill", color: .red)
                            .foregroundStyle(.red)
                    }
                    .disabled(isChangingData)

                    Button(role: .destructive) {
                        showFullResetConfirmation = true
                    } label: {
                        SettingsListItem(text: "Delete All Data", icon: "trash.circle.fill", color: .red)
                            .foregroundStyle(.red)
                    }
                    .disabled(isChangingData)
                } footer: {
                    if config.hasPendingCloudDeletion {
                        Text("iCloud deletion is pending. Sync stays off. Close Syl from the App Switcher, then reopen it while connected to iCloud to finish deletion.")
                    } else if config.supportsCloudSync {
                        Text("Delete All Data removes Syl data here. iCloud deletion finishes after you close Syl from the App Switcher and reopen it. Other devices update after iCloud syncs; copies saved outside Syl remain.")
                    } else {
                        Text("Delete All Data removes Syl data, settings, and the local CSV export. Copies saved outside Syl remain.")
                    }
                }

                #if DEBUG
                Section("Debug") {
                    Button(role: .destructive) {
                        config.resetRemoteSetup()
                        UserDefaults.standard.removeObject(forKey: "hasOpenedAppOnce")
                    } label: {
                        SettingsListItem(text: "Reset Onboarding", icon: "arrow.counterclockwise", color: .orange)
                            .foregroundStyle(.orange)
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .settingsBackground()
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .appearance:
                    AppearanceSettingsSection()
                case .budget:
                    BudgetSettingsSection()
                case .recurringExpenses:
                    RecurringExpensesSettingsSection()
                case .notifications:
                    NotificationsSettingsSection()
                case .tags:
                    TagsSettingsSection()
                case .backup:
                    ExpenseBackupSettingsSection()
                case .privacy:
                    PrivacyWebView()
                }
            }
            .alert("Choose What to Delete", isPresented: $showExpenseDeletionOptions) {
                Button("Delete Expenses Only", role: .destructive) {
                    Task { await performDataOperation(.expensesOnly) }
                }
                .disabled(isChangingData)
                Button("Delete Expenses and Recurring Rules", role: .destructive) {
                    Task { await performDataOperation(.expensesAndRecurringRules) }
                }
                .disabled(isChangingData)
                Button("Cancel", role: .cancel) {}
            } message: {
                if config.supportsCloudSync {
                    Text("Both options remove expenses from this iPhone. Keeping recurring rules lets them create new expenses. If expense sync was active when Syl opened, deletions can reach iCloud and other devices. If it was inactive, old iCloud expenses may return when sync is enabled later.")
                } else {
                    Text("Both options remove expenses from this device. Keeping recurring rules lets them create new expenses.")
                }
            }
            .alert("Delete All Data?", isPresented: $showFullResetConfirmation) {
                Button("Delete All Data", role: .destructive) {
                    Task { await performDataOperation(.fullReset) }
                }
                .disabled(isChangingData)
                Button("Cancel", role: .cancel) {}
            } message: {
                if config.supportsCloudSync {
                    Text("This removes expenses, recurring rules, tags, settings, and Syl's local CSV export here, then deletes Syl's iCloud data after you close Syl from the App Switcher and reopen it, even if sync is off. Sync stays off until deletion finishes. Other devices may show old data until iCloud updates. Copies saved or shared outside Syl must be deleted separately.")
                } else {
                    Text("This permanently deletes expenses, recurring rules, tags, settings, and Syl's local CSV export from this device. Copies saved or shared outside Syl must be deleted separately.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let activeDataOperation {
                    ProgressView(activeDataOperation.progressMessage)
                        .font(.subheadline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                        .accessibilityLabel("\(activeDataOperation.progressMessage). In progress.")
                }
            }
        }
    }

    private func performDataOperation(_ operation: DataOperation) async {
        guard activeDataOperation == nil else { return }
        activeDataOperation = operation
        router.showToast(SageToast(message: operation.progressMessage + "…", kind: .progress))
        defer { activeDataOperation = nil }

        await Task.yield()

        let deletionService = DataDeletionService(modelContext: modelContext)
        do {
            switch operation {
            case .expensesOnly:
                try deletionService.deleteExpenses(includeRecurringRules: false)
            case .expensesAndRecurringRules:
                try deletionService.deleteExpenses(includeRecurringRules: true)
                reminders?.refresh()
            case .fullReset:
                let previous = config.prepareForDataDeletion()
                do {
                    try deletionService.deleteAllUserData()
                } catch {
                    config.cancelDataDeletion(previous: previous)
                    throw error
                }
                _ = config.resetAllSettings()
                reminders?.refresh()
                publishEmptyWatchSnapshot()
                WidgetCenter.shared.reloadAllTimelines()
                if config.hasPendingCloudDeletion {
                    config.markLocalDeletionComplete()
                    return
                }
                UserDefaults.standard.removeObject(forKey: "hasOpenedAppOnce")
            }

            WidgetCenter.shared.reloadAllTimelines()
            router.showToast(SageToast(message: operation.successMessage, kind: .success))
        } catch {
            // Only pending model changes can be rolled back, not an already-removed CSV.
            deletionService.rollback()
            router.showToast(
                SageToast(message: operation.failureMessage, kind: .error)
            )
        }
    }

    private func publishEmptyWatchSnapshot() {
        guard !UITestConfiguration.isEnabled,
              let snapshot = try? WatchSnapshotBuilder.makeSnapshot(
                container: modelContext.container,
                categoryColors: config.categoryColors,
                currencyCode: config.ledgerCurrencyCode,
                monthlyBudget: 0
              ) else { return }
        WatchSnapshotSender.shared.sendUpdatedMonthlySnapshot(snapshot: snapshot)
    }
}

private enum DataOperation {
    case expensesOnly
    case expensesAndRecurringRules
    case fullReset

    var progressMessage: String {
        switch self {
        case .expensesOnly: "Deleting expenses"
        case .expensesAndRecurringRules: "Deleting expenses and recurring rules"
        case .fullReset: "Deleting all data"
        }
    }

    var successMessage: String {
        switch self {
        case .expensesOnly: "Expenses removed from this device. Recurring rules are still active."
        case .expensesAndRecurringRules: "Expenses and recurring rules removed from this device."
        case .fullReset: "Syl data, settings, and local export deleted."
        }
    }

    var failureMessage: String {
        switch self {
        case .expensesOnly: "Syl could not delete the expenses. Check storage and try again."
        case .expensesAndRecurringRules: "Syl could not delete the expenses and recurring rules. Check storage and try again."
        case .fullReset: "Syl could not finish deleting all data. Some data may already be removed. Check storage and try again."
        }
    }
}

struct SettingsListItem: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .frame(width: 35, height: 35)
                    .foregroundStyle(color)
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(text)
                .fontWeight(.bold)
        }
    }
}

#Preview {
    @Previewable @State var appConfig: AppConfiguration = .preview
    SettingsView()
        .environment(appConfig)
        .environment(AppRouter())
        .modelContainer(SageModelContainer.preview)
}
