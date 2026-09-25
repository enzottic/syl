import SwiftUI
import SwiftData
import SageKit
import UserNotifications

struct NotificationsSettingsSection: View {
    var body: some View {
        List {
            RecurringNotificationsSettingsSection()
            DailyExpenseReminderSettingsSection()
        }
        .settingsBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RecurringNotificationsSettingsSection: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.recurringReminders) private var reminders
    @Query private var rules: [RecurringExpenseRule]
    @State private var isRequestingPermission = false
    @State private var permissionError: String?

    var body: some View {
        @Bindable var config = config
        Section {
            Toggle("Bill Reminders", isOn: Binding(
                get: { config.billRemindersEnabled && !permissionDenied },
                set: { setRemindersEnabled($0) }
            ))
            .disabled(isRequestingPermission)
            .accessibilityIdentifier("bill-reminders-toggle")

            if config.billRemindersEnabled && !permissionDenied {
                Picker("Remind Me", selection: $config.billReminderDaysBefore) {
                    Text("1 day before").tag(1)
                    ForEach(2...7, id: \.self) { days in
                        Text("\(days) days before").tag(days)
                    }
                }
                .accessibilityIdentifier("bill-reminder-days")
                .accessibilityValue(config.billReminderDaysBefore == 1
                    ? Text("1 day before")
                    : Text("\(config.billReminderDaysBefore) days before"))

                ReminderTimePicker(minutes: $config.billReminderTimeMinutes)
                    .accessibilityIdentifier("bill-reminder-time")

                Toggle("Hide Expense Details", isOn: $config.hideBillReminderDetails)
                    .accessibilityIdentifier("bill-reminder-privacy")
            }
        } header: {
            Text("Recurring Notifications")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("One summary at your chosen local time for all recurring expenses scheduled on the target day.")
                NotificationPermissionFooter(isDenied: permissionDenied, error: permissionError)
            }
        }
        .onChange(of: config.billReminderDaysBefore) { reminders?.refresh() }
        .onChange(of: config.billReminderTimeMinutes) { reminders?.refresh() }
        .onChange(of: config.hideBillReminderDetails) { reminders?.refresh() }
    }

    private var permissionDenied: Bool {
        reminders?.scheduler.authorizationStatus == .denied
    }

    private func setRemindersEnabled(_ enabled: Bool) {
        config.billRemindersEnabled = enabled
        permissionError = nil
        guard enabled, reminders != nil else {
            reminders?.refresh()
            return
        }
        isRequestingPermission = true
        Task { @MainActor in
            defer {
                isRequestingPermission = false
                reminders?.refresh()
            }
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
                catch {
                    permissionError = error.localizedDescription
                    config.billRemindersEnabled = false
                }
            }
        }
    }
}
