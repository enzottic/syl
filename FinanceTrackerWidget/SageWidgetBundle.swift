//
//  SageWidgetBundle.swift
//  FinanceTrackerWidget
//
//  Created by Enzo on 10/5/25.
//

import WidgetKit
import SwiftUI
import AppIntents
import SageKit

@main
struct SageWidgetBundle: WidgetBundle {
    init() {
        AppIntentDependencies.register()
    }

    var body: some Widget {
        DailyChartWidget()
        RecentExpensesWidget()
        CategorySpotlightWidget()
        MonthlySummaryWidget()
    }
}

struct WidgetAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [SageKitPackage.self]
    }
}
