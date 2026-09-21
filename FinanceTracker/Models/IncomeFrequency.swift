import Foundation

enum IncomeFrequency: String, CaseIterable, Identifiable {
    case monthly = "Monthly"
    case biweekly = "Biweekly"
    case weekly = "Weekly"

    var id: Self { self }

    var periodDescription: String {
        switch self {
        case .monthly: "per month, after tax"
        case .biweekly: "every 2 weeks, after tax"
        case .weekly: "per week, after tax"
        }
    }

    var calculationDescription: String {
        switch self {
        case .monthly: "Your take-home pay each month."
        case .biweekly: "Based on 26 paychecks per year."
        case .weekly: "Based on 52 paychecks per year."
        }
    }

    func monthlyIncome(for amount: Int) -> Int {
        let paymentsPerYear: Double = switch self {
        case .monthly: 12
        case .biweekly: 26
        case .weekly: 52
        }
        // Onboarding and the saved budget use whole currency units.
        return Int((Double(amount) * paymentsPerYear / 12).rounded())
    }
}
