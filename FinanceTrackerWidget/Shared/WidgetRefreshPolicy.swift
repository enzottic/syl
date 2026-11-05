import Foundation
import WidgetKit

/// Syl reloads widget timelines whenever data changes on this device or arrives from iCloud.
/// The hourly refresh catches iCloud changes that arrive while Syl isn't running, and the
/// midnight refresh rolls the widgets over to a new day or month on time.
enum WidgetRefreshPolicy {
    static func standard(after date: Date, calendar: Calendar = .current) -> TimelineReloadPolicy {
        let nextHour = date.addingTimeInterval(3_600)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else {
            return .after(nextHour)
        }
        return .after(min(nextHour, tomorrow))
    }
}
