//
//  SageWidgetBundle.swift
//  FinanceTrackerWidget
//
//  Created by Enzo on 10/5/25.
//

import WidgetKit
import SwiftUI

@main
struct SageWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyChartWidget()
        RecentExpensesWidget()
        CategorySpotlightWidget()
        MonthlySummaryWidget()
    }
}
