//
//  NotificationDelegate.swift
//  FinanceTracker
//

import UserNotifications
import Observation
import SageKit

@MainActor @Observable
final class ReminderNavigation {
    static let shared = ReminderNavigation()
    var isRequested = false
    var isExpenseEntryRequested = false
}

/// Without a delegate, iOS silently drops notifications that fire while the app is foreground.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let identifier = response.notification.request.identifier
        await MainActor.run {
            if RecurringReminderPlan.owns(identifier) {
                ReminderNavigation.shared.isRequested = true
            } else if identifier == DailyExpenseReminderScheduler.identifier {
                ReminderNavigation.shared.isExpenseEntryRequested = true
            }
        }
    }
}
