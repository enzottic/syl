import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
public final class DailyExpenseReminderScheduler {
    public static let identifier = "sage.daily-expense-entry.v1"

    public private(set) var errorMessage: String?
    public private(set) var isRefreshing = false
    public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private struct Inputs: Equatable {
        let enabled: Bool
        let timeMinutes: Int
    }

    private let client: any NotificationClient
    @ObservationIgnored private var inputs: Inputs?
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var worker: Task<Void, Never>?

    public init(client: (any NotificationClient)? = nil) {
        self.client = client ?? UNNotificationClient()
    }

    /// Reads permission without prompting and coalesces refreshes into one worker.
    public func refresh(enabled: Bool, timeMinutes: Int = 1200) {
        inputs = Inputs(enabled: enabled, timeMinutes: (0..<1440).contains(timeMinutes) ? timeMinutes : 1200)
        revision &+= 1
        guard worker == nil else { return }
        isRefreshing = true
        worker = Task { await run() }
    }

    public func waitUntilIdle() async {
        while let worker { await worker.value }
    }

    private func run() async {
        while let inputs {
            let currentRevision = revision
            errorMessage = nil
            await reconcile(inputs, revision: currentRevision)
            if currentRevision == revision { break }
        }
        inputs = nil
        isRefreshing = false
        worker = nil
    }

    private func reconcile(_ inputs: Inputs, revision currentRevision: UInt64) async {
        let status = await client.authorizationStatus()
        guard currentRevision == revision else { return }
        authorizationStatus = status
        let authorized = status == .authorized || status == .provisional || status == .ephemeral
        guard inputs.enabled && authorized else {
            client.removePending([Self.identifier])
            client.removeDelivered([Self.identifier])
            return
        }

        let pending = await client.pendingRequests()
        guard currentRevision == revision else { return }
        guard pending.filter({ $0.identifier != Self.identifier }).count < 64 else {
            client.removePending([Self.identifier])
            errorMessage = "Daily expense reminder could not be scheduled because the notification queue is full."
            return
        }

        // Hour/minute only keeps the repeating reminder in floating device-local time.
        let components = DateComponents(hour: inputs.timeMinutes / 60, minute: inputs.timeMinutes % 60)
        let content = UNMutableNotificationContent()
        content.title = "Daily Expense Reminder"
        content.body = "Add expenses from the day."
        content.sound = .default
        if let existing = pending.first(where: { $0.identifier == Self.identifier }),
           let trigger = existing.trigger as? UNCalendarNotificationTrigger,
           trigger.repeats, trigger.dateComponents == components,
           existing.content.title == content.title, existing.content.body == content.body {
            return
        }

        let request = UNNotificationRequest(
            identifier: Self.identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        do {
            try await client.add(request)
        } catch {
            // A failed replacement must not leave the obsolete time queued.
            client.removePending([Self.identifier])
            if currentRevision == revision { errorMessage = error.localizedDescription }
            return
        }
        // Adds cannot be cancelled. Remove obsolete results before processing the latest inputs.
        if currentRevision != revision && self.inputs != inputs {
            client.removePending([Self.identifier])
        }
    }
}
