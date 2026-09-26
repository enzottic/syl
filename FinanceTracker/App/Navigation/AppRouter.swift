//
//  AppRouter.swift
//  FinanceTracker
//
//  Created by Enzo on 3/17/26.
//
import SwiftUI
import SageKit

@Observable
@MainActor
final class AppRouter {
    var selectedTab: SageTab = .home

    // Per-tab navigation stacks (typed).
    var homePath: [AppRoute] = []
    var expensesPath: [AppRoute] = []
    var searchPath: [AppRoute] = []
    var settingsPath: [SettingsPage] = []

    /// Single modal presented above any tab.
    var presentedSheet: SageSheet?

    /// "Show All" courier: hands the dashboard's month to the Expenses tab.
    var expensesMonth: Date = .now
    var expensesRequestID = UUID()

    var toast: SageToast?

    private var dismissTask: Task<Void, Never>?
    var expenseDraftNavigationHandler: ((Date) -> Void)?

    // MARK: - Navigation

    func showExpenses(for month: Date) {
        if let expenseDraftNavigationHandler {
            expenseDraftNavigationHandler(month)
            return
        }
        completeShowExpenses(for: month)
    }

    func completeShowExpenses(for month: Date) {
        expensesMonth = month
        expensesPath.removeAll()
        expensesRequestID = UUID()
        selectedTab = .expenses
    }

    /// Appends a route to the currently visible tab's stack.
    func push(_ route: AppRoute) {
        switch selectedTab {
        case .home: homePath.append(route)
        case .expenses: expensesPath.append(route)
        case .search: searchPath.append(route)
        default: break
        }
    }

    func presentSheet(_ sheet: SageSheet) {
        presentedSheet = sheet
    }

    func navigate(to link: SageDeepLink) {
        switch link {
        case .addExpense:
            presentSheet(.addExpense(nil))
        }
    }

    func importReceipt(from url: URL) {
        do {
            let receiptData = try ReceiptImageImport.loadData(from: url)
            presentSheet(.addExpense(nil, receiptData: receiptData))
        } catch {
            showToast(
                SageToast(
                    message: "Syl could not open that receipt image.",
                    kind: .error
                )
            )
        }
    }

    // MARK: - Toast

    func showToast(_ toast: SageToast) {
        dismissTask?.cancel()
        // The presenting view owns animation so it can honor Reduce Motion.
        self.toast = toast

        guard toast.kind != .progress else { return }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.toast = nil
        }
    }
}
