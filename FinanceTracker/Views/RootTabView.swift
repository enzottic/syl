//
//  RootTabView.swift
//  FinanceTracker
//
//  Created by Enzo on 9/21/25.
//

import SwiftUI
import SwiftData
import SageKit

struct RootTabView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appRouter = AppRouter()
    @State private var whatsNewRelease: WhatsNewRelease?
    @State private var query: String? = nil
    @State private var reminderNavigation = ReminderNavigation.shared

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        @Bindable var appRouter = appRouter

        TabView(selection: $appRouter.selectedTab) {

            Tab("Home", systemImage: "house", value: SageTab.home) {
                DashboardView()
            }

            Tab("Expenses", systemImage: "list.bullet", value: SageTab.expenses) {
                ExpensesView(month: appRouter.expensesMonth)
            }

            Tab("Stats", systemImage: "chart.bar", value: SageTab.stats) {
                StatsView()
            }

            // Keep Settings as a real tab on every idiom: a sidebar-only entry point
            // disappears in compact iPad widths (Slide Over, narrow Split View).
            Tab("Settings", systemImage: "gear", value: SageTab.settings) {
                SettingsView()
            }

            Tab("Search", systemImage: "magnifyingglass", value: SageTab.search, role: .search) {
                SearchExpensesView()
            }

        }
        .modifier(PlatformTabViewStyle(isPad: isPad))
        .tabViewSearchActivation(.searchTabSelection)
        .accessibilityIdentifier("main-tab-view")
        .sheet(item: $appRouter.presentedSheet) { sheet in
            switch sheet {
            case .addExpense(let expense, let receiptData, _):
                NewAddExpenseSheet(expense: expense, receiptData: receiptData)
            }
        }
        .overlay(alignment: .top) {
            ZStack {
                if let toast = appRouter.toast {
                    ToastPill(toast: toast)
                        .padding(.top, 60)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .milliseconds(700))
                            let prefix: String
                            switch toast.kind {
                            case .progress: prefix = "In progress"
                            case .success: prefix = "Success"
                            case .error: prefix = "Error"
                            }
                            AccessibilityNotification.Announcement("\(prefix): \(toast.message)").post()
                        }
                }
            }
            .animation(
                reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4),
                value: appRouter.toast == nil
            )
        }
        .sensoryFeedback(.success, trigger: appRouter.toast?.kind == .success) { _, isSuccess in isSuccess }
        .environment(appRouter)
        .background(.background)
        .tint(.sage)
        .onOpenURL { url in
            if url.isFileURL {
                appRouter.importReceipt(from: url)
            } else if let link = SageDeepLink(url: url) {
                appRouter.navigate(to: link)
            }
        }
        .task {
            if !reminderNavigation.isRequested && !reminderNavigation.isExpenseEntryRequested {
                whatsNewRelease = WhatsNewStore.releaseToPresent()
            }
            WhatsNewStore.markCurrentVersionSeen()
        }
        .onChange(of: reminderNavigation.isRequested, initial: true) { openReminderDashboardIfReady() }
        .onChange(of: reminderNavigation.isExpenseEntryRequested, initial: true) { openReminderDashboardIfReady() }
        .onChange(of: appRouter.presentedSheet == nil) { openReminderDashboardIfReady() }
        .onChange(of: whatsNewRelease == nil) { openReminderDashboardIfReady() }
        .sheet(item: $whatsNewRelease) { release in
            WhatsNewSheet(release: release)
        }
    }

    private func openReminderDashboardIfReady() {
        // Preserve an open expense draft; cold-launch requests wait for the normal app gates.
        guard reminderNavigation.isRequested || reminderNavigation.isExpenseEntryRequested,
              appRouter.presentedSheet == nil,
              whatsNewRelease == nil else { return }
        reminderNavigation.isExpenseEntryRequested = false
        reminderNavigation.isRequested = false
        appRouter.homePath.removeAll()
        appRouter.selectedTab = .home
    }

}

private struct PlatformTabViewStyle: ViewModifier {
    let isPad: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPad {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}


#Preview {
    RootTabView()
        .environmentInjection()
}
