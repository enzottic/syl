import Foundation

public nonisolated enum RecurringExpenseOccurrence {
    // The exact conversion used by repair, without trapping on untrusted backup dates.
    public static func safeKey(ruleID: UUID, scheduledDate: Date) -> String? {
        guard let milliseconds = safeMilliseconds(scheduledDate) else { return nil }
        
        return "v1:\(ruleID.uuidString.lowercased()):\(milliseconds)"
    }

    public static func safeMilliseconds(_ date: Date) -> Int64? {
        let value = (date.timeIntervalSince1970 * 1_000).rounded()
        guard value.isFinite else { return nil }
        
        return Int64(exactly: value)
    }

    public static func isValidKey(_ key: String, ruleID: UUID) -> Bool {
        let prefix = "v1:\(ruleID.uuidString.lowercased()):"
        guard key.hasPrefix(prefix), let milliseconds = Int64(key.dropFirst(prefix.count)) else { return false }
        
        return key == prefix + String(milliseconds)
    }

    public static func scheduledDate(forKey key: String, ruleID: UUID) -> Date? {
        guard isValidKey(key, ruleID: ruleID),
              let milliseconds = key.split(separator: ":").last.flatMap({ Int64($0) }) else { return nil }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    // Returns one stable identity for a rule occurrence on all devices.
    // CloudKit stores dates with millisecond precision, so the scheduled date uses the same scale.
    public static func key(ruleID: UUID, scheduledDate: Date) -> String {
        let milliseconds = Int64((scheduledDate.timeIntervalSince1970 * 1_000).rounded())
        return "v1:\(ruleID.uuidString.lowercased()):\(milliseconds)"
    }
}
