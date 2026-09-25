import SwiftUI
import SageKit
import UserNotifications

struct DailyExpenseReminderSettingsSection: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.recurringReminders) private var reminders
    @State private var requestingPermission = false
    @State private var permissionError: String?

    var body: some View {
        @Bindable var config = config
        Section {
            Toggle("Daily Reminder", isOn: Binding(
                get: { config.dailyExpenseReminderEnabled && !permissionDenied },
                set: { setEnabled($0) }
            ))
            .disabled(requestingPermission)
            .accessibilityIdentifier("daily-expense-reminder-toggle")

            if config.dailyExpenseReminderEnabled && !permissionDenied {
                ReminderTimePicker(minutes: $config.dailyExpenseReminderTimeMinutes)
                    .accessibilityIdentifier("daily-expense-reminder-time")
            }
        } header: {
            Text("Daily Reminder")
        } footer: {
            NotificationPermissionFooter(isDenied: permissionDenied, error: permissionError)
        }
        .onChange(of: config.dailyExpenseReminderTimeMinutes) { reminders?.refresh() }
    }

    private var permissionDenied: Bool {
        reminders?.dailyScheduler.authorizationStatus == .denied
    }

    private func setEnabled(_ enabled: Bool) {
        config.dailyExpenseReminderEnabled = enabled
        permissionError = nil
        guard enabled, reminders != nil else {
            reminders?.refresh()
            return
        }
        requestingPermission = true
        Task { @MainActor in
            defer {
                requestingPermission = false
                reminders?.refresh()
            }
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
                catch {
                    permissionError = error.localizedDescription
                    config.dailyExpenseReminderEnabled = false
                }
            }
        }
    }
}
