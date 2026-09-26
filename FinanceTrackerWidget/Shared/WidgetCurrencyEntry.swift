//
//  WidgetCurrencyEntry.swift
//  FinanceTracker
//
//  Created by Enzo on 10/7/25.
//

import Foundation
import WidgetKit

protocol WidgetCurrencyEntry: TimelineEntry {
    var currencyCode: String? { get }
}

extension WidgetCurrencyEntry {
    func currencyString(_ amount: Double) -> String {
        if let currencyCode {
            return amount.formatted(.currency(code: currencyCode))
        }
        return amount.formatted()
    }
}
