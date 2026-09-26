//
//  WatchSnapshot.swift
//  FinanceTracker
//
//  Created by Enzo on 9/10/26.
//
import Foundation
import SwiftUI

public struct WatchSnapshot: Codable, Identifiable {
    /// Key for the encoded snapshot in the WatchConnectivity application context.
    public static let applicationContextKey = "snapshot"

    public let generatedAt: Date
    
    public let monthStart: Date
    public let monthEnd: Date
    public let timeZoneIdentifier: String
    public let currencyCode: String
   
    public let totalSpent: Double
    public let monthlyBudget: Double
    public let categories: [WatchCategorySnapshot]
    
    public let daysInMonth: Int
    public let spendingPoints: [WatchSpendingPoint]
    public let recentDailySpending: [WatchDailySpending]?
    
    public var id: Date { generatedAt }
    
    public init(
        generatedAt: Date,
        monthStart: Date,
        monthEnd: Date,
        timeZoneIdentifier: String,
        currencyCode: String,
        totalSpent: Double,
        monthlyBudget: Double,
        categories: [WatchCategorySnapshot],
        daysInMonth: Int,
        spendingPoints: [WatchSpendingPoint],
        recentDailySpending: [WatchDailySpending]? = nil
    ) {
        self.generatedAt = generatedAt
        self.monthStart = monthStart
        self.monthEnd = monthEnd
        self.timeZoneIdentifier = timeZoneIdentifier
        self.currencyCode = currencyCode
        self.totalSpent = totalSpent
        self.monthlyBudget = monthlyBudget
        self.categories = categories
        self.daysInMonth = daysInMonth
        self.spendingPoints = spendingPoints
        self.recentDailySpending = recentDailySpending
    }
}

public struct WatchDailySpending: Codable, Identifiable {
    public let date: Date
    public let amount: Double
    public var id: Date { date }

    public init(date: Date, amount: Double) {
        self.date = date
        self.amount = amount
    }
}

extension WatchSnapshot {
    public var reportingCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    public var monthLabel: String {
        monthStart.formatted(Date.FormatStyle(calendar: reportingCalendar, timeZone: reportingCalendar.timeZone)
            .month(.wide).year())
    }

    public func isStale(at date: Date) -> Bool {
        date >= monthEnd || date.timeIntervalSince(generatedAt) >= 86_400
    }

    // Older delivered snapshots contain only this month's cumulative points.
    public var recentDays: [WatchDailySpending] {
        if let recentDailySpending { return recentDailySpending }
        var previous = 0.0
        return spendingPoints.map { point in
            let amount = point.cumulativeSpent - previous
            previous = point.cumulativeSpent
            return WatchDailySpending(
                date: reportingCalendar.date(byAdding: .day, value: point.day - 1, to: monthStart) ?? monthStart,
                amount: amount
            )
        }.suffix(7).map { $0 }
    }
}


public struct WatchCategorySnapshot: Codable, Identifiable {
    public let categoryName: String
    public let totalSpent: Double
    public let monthlyBudget: Double
    public let color: SnapshotColor
    public let spendingPoints: [WatchSpendingPoint]
    
    public var id: String { categoryName }
    
    public init(
        categoryName: String,
        totalSpent: Double,
        monthlyBudget: Double,
        color: SnapshotColor,
        spendingPoints: [WatchSpendingPoint]
    ) {
        self.categoryName = categoryName
        self.totalSpent = totalSpent
        self.monthlyBudget = monthlyBudget
        self.color = color
        self.spendingPoints = spendingPoints
    }
}

public struct SnapshotColor: Codable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double
    
    init(red: Double, green: Double, blue: Double, opacity: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}

extension SnapshotColor {
    public init(_ color: Color, environment: EnvironmentValues) {
        let resolved = color.resolve(in: environment)
        
        self.init(
            red: Double(resolved.red),
            green: Double(resolved.green),
            blue: Double(resolved.blue),
            opacity: Double(resolved.opacity)
        )
    }
    
    public var color: Color {
        Color(
            .sRGB,
            red: red,
            green: green,
            blue: blue,
            opacity: opacity
        )
    }
}

public struct WatchSpendingPoint: Codable, Identifiable {
    public let day: Int
    public let cumulativeSpent: Double
    
    public var id: Int { day }
    
    public init(day: Int, cumulativeSpent: Double) {
        self.day = day
        self.cumulativeSpent = cumulativeSpent
    }
}

extension WatchSnapshot {
    public static var preview: WatchSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        let generatedAt = calendar.date(byAdding: .day, value: 10, to: monthStart)!
        var environment = EnvironmentValues()
        environment.colorScheme = .dark

        // Daily amounts in cents keep the fixture's category and overall totals consistent.
        let samples: [(name: String, budget: Double, color: Color, dailyCents: [Int])] = [
            ("Needs", 3800, .blue, [150000, 0, 8245, 0, 4500, 0, 12680, 0, 0, 5620, 0]),
            ("Wants", 2280, .green, [0, 1875, 0, 4299, 0, 6500, 0, -1200, 2499, 0, 7950]),
            ("Savings", 1520, .orange, [60000, 0, 0, 0, 0, 0, 0, 0, 0, 60000, 0])
        ]
        let categories = samples.map { sample in
            var cumulativeCents = 0
            let points = sample.dailyCents.enumerated().map { index, cents in
                cumulativeCents += cents
                return WatchSpendingPoint(day: index + 1, cumulativeSpent: Double(cumulativeCents) / 100)
            }
            return WatchCategorySnapshot(
                categoryName: sample.name,
                totalSpent: points.last?.cumulativeSpent ?? 0,
                monthlyBudget: sample.budget,
                color: SnapshotColor(sample.color, environment: environment),
                spendingPoints: points
            )
        }
        var cumulativeCents = 0
        let points = samples[0].dailyCents.indices.map { index in
            cumulativeCents += samples.reduce(0) { $0 + $1.dailyCents[index] }
            return WatchSpendingPoint(day: index + 1, cumulativeSpent: Double(cumulativeCents) / 100)
        }

        return WatchSnapshot(
            generatedAt: generatedAt,
            monthStart: monthStart,
            monthEnd: monthEnd,
            timeZoneIdentifier: calendar.timeZone.identifier,
            currencyCode: "USD",
            totalSpent: points.last?.cumulativeSpent ?? 0,
            monthlyBudget: samples.reduce(0) { $0 + $1.budget },
            categories: categories,
            daysInMonth: 30,
            spendingPoints: points
        )
    }
}
