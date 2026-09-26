import CoreData
import SageKit
import SwiftData
import SwiftUI
import UserNotifications

@MainActor
final class RecurringReminderCoordinator {
    let scheduler: RecurringReminderScheduler
    let dailyScheduler = DailyExpenseReminderScheduler()
    private let container: ModelContainer
    private var configuration: AppConfiguration?
    private var observers: [NSObjectProtocol] = []

    init(container: ModelContainer) {
        self.container = container
        scheduler = RecurringReminderScheduler(defaults: SagePreferences.defaults)
    }

    func start(configuration: AppConfiguration) {
        self.configuration = configuration
        
        let observerNames = [
            ModelContext.didSave,
            UIApplication.didBecomeActiveNotification,
            UIApplication.significantTimeChangeNotification,
            NSNotification.Name.NSSystemTimeZoneDidChange,
            NSLocale.currentLocaleDidChangeNotification
        ]
        
        if observers.isEmpty {
            for name in observerNames {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        Task { @MainActor [weak self] in self?.refresh() }
                    }
                )
            }
            
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSPersistentCloudKitContainer.eventChangedNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let
                            event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                            event.type == .import,
                            event.endDate != nil else { return }
                    
                    Task { @MainActor [weak self] in self?.refresh() }
                }
            )
        }
        
        refresh()
    }

    func refresh() {
        guard let configuration else { return }
        
        let enabled = configuration.billRemindersEnabled
        let days = configuration.billReminderDaysBefore
        let time = configuration.billReminderTimeMinutes
        let hideDetails = configuration.hideBillReminderDetails
        let currency = configuration.ledgerCurrencyCode
        
        dailyScheduler.refresh(
            enabled: configuration.dailyExpenseReminderEnabled,
            timeMinutes: configuration.dailyExpenseReminderTimeMinutes
        )
        
        scheduler.refresh(
            enabled: enabled,
            hideDetails: hideDetails
        ) { [container] in
            // A fresh context observes saved edits and imported rules, not cached screen models.
            let context = ModelContext(container)
            let rules = try context.fetch(FetchDescriptor<RecurringExpenseRule>())
            return try RecurringReminderPlan.summaries(
                rules: rules, daysBefore: days, timeMinutes: time, hideDetails: hideDetails,
                currencyCode: currency, now: .now
            )
        }
    }
}

extension EnvironmentValues {
    @Entry var recurringReminders: RecurringReminderCoordinator? = nil
}
