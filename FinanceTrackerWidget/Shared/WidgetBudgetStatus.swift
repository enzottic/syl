import Foundation
import SageKit

extension WidgetCurrencyEntry {
    /// A short description of a budget status, such as "$120.00 left", for widget text and VoiceOver.
    func description(of status: BudgetStatus) -> String {
        switch status {
        case .noBudget: "No budget"
        case .noTarget: "No target"
        case .underBudget(let remaining): "\(currencyString(remaining)) left"
        case .overBudget(let amount): "\(currencyString(amount)) over budget"
        case .belowTarget(let remaining): "\(currencyString(remaining)) to target"
        case .targetReached: "Target reached"
        }
    }
}
