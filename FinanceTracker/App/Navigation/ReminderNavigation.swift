import Observation

@MainActor @Observable
final class ReminderNavigation {
    static let shared = ReminderNavigation()
    var isRequested = false
    var isExpenseEntryRequested = false
}
