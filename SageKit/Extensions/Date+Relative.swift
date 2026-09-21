//
//  Date+Relative.swift
//  FinanceTracker
//
//  Created by Enzo on 9/21/25.
//

import Foundation

public extension Date {
    func relative(to now: Date = .now, calendar: Calendar = .current) -> String {
        
        // Check if it's today
        if calendar.isDate(self, inSameDayAs: now) {
            return "Today"
        }
        
        // Check if it's yesterday
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(self, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        
        // Check if it's within the last week (2-6 days ago)
        let daysDifference = calendar.dateComponents([.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: now)).day ?? 0
        if daysDifference >= 2 && daysDifference < 7 {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "EEEE" // Full day name
            return formatter.string(from: self)
        }
        
        // Default to MM/DD/YYYY format
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M/d/yyyy"
        return formatter.string(from: self)
    }
}

