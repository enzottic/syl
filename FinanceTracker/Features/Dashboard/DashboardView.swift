//
//  DashboardView.swift
//  FinanceTracker
//
//  Created by Enzo on 7/12/26.
//
import SwiftUI
import SwiftData
import SageKit

struct DashboardView: View {
    @Environment(AppRouter.self) var appRouter
    @Environment(AppConfiguration.self) var config
    
    @State private var selectedMonth: Date
    @State private var showingWidgetOrderSheet = false

    init() {
        _selectedMonth = State(initialValue: .now)
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        @Bindable var appRouter = appRouter
        NavigationStack(path: $appRouter.homePath) {
            DashboardVisibleWidgets(selectedMonth: selectedMonth, order: config.dashboardWidgetOrder) { widgets in
                GeometryReader { geometry in
                    if geometry.size.width >= DashboardGridLayout.minimumGridWidth {
                        ScrollView {
                            DashboardGridLayout() {
                                ForEach(widgets) { id in
                                    composedWidget(id.widget, presentation: .full)
                                        .accessibilityElement(children: .contain)
                                        .accessibilityIdentifier("dashboard-widget-\(id.rawValue)")
                                }
                            }
                            .buttonStyle(.borderless)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                    } else {
                        List {
                            ForEach(widgets) { id in
                                widgetView(for: id.widget, layout: .full)
                            }
                        }
                        .listSectionSpacing(12)
                    }
                }
            }
            .navigationTitle(selectedMonth.formatted(.dateTime.month(.wide).year()))
            .scrollContentBackground(.hidden)
            .background(.sageBackground)
            .gradientBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Reorder Widgets", systemImage: "arrow.up.arrow.down") {
                            showingWidgetOrderSheet = true
                        }
                    } label: {
                        Label("Dashboard Options", systemImage: "ellipsis")
                    }
                    .accessibilityIdentifier("dashboard-options")
                }
                SageToolbar(
                    onPrevious: {
                        selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                    },
                    onNext: {
                        selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                    },
                    onAdd: { appRouter.presentSheet(.addExpense(nil)) },
                    isNextDisabled: isCurrentMonth
                )
            }
            .sheet(isPresented: $showingWidgetOrderSheet) {
                DashboardWidgetOrderSheet()
            }
            .detailRouteDestinations()
        }
    }

    @ViewBuilder
    func widgetView(for widget: DashboardWidget, layout: DashboardWidgetLayout, usesCards: Bool = false) -> some View {
        switch widget {
        case .monthlyOverview: MonthlyOverviewWidget(selectedMonth: selectedMonth)
        case .expenseCalendar: ExpenseCalendarWidget(selectedMonth: selectedMonth)
        case .mostSpentTags:
            MostSpentTagsWidget(selectedMonth: selectedMonth, layout: layout)
        case .categoryUtilization: CategoryUtilizationWidget(selectedMonth: selectedMonth, usesCards: usesCards)
        case .upcomingRecurring: UpcomingRecurringWidget(layout: layout)
        case .recentExpenses(let rowStyle):
            RecentExpensesDashboardWidget(selectedMonth: selectedMonth, rowStyle: rowStyle, embedsList: usesCards)
        }
    }

    @ViewBuilder
    private func composedWidget(
        _ widget: DashboardWidget,
        presentation: DashboardWidgetLayout
    ) -> some View {
        if widget == .categoryUtilization {
            widgetView(for: widget, layout: presentation, usesCards: true)
        } else if presentation == .compact && (widget == .mostSpentTags || widget == .upcomingRecurring) {
            // These widgets own their cards so empty content has no background.
            widgetView(for: widget, layout: presentation, usesCards: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            // Keep Section headers and rows in one card before applying sizing
            // and backgrounds; otherwise SwiftUI styles each child separately.
            VStack(alignment: .leading, spacing: 12) {
                widgetView(for: widget, layout: presentation, usesCards: true)
            }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: widget == .monthlyOverview ? .center : .topLeading)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: .rect(cornerRadius: DashboardCardStyle.cornerRadius)
                )
        }
    }
}

private struct DashboardGridLayout: Layout {
    // Two 340-point columns, their spacing, and the dashboard’s horizontal padding.
    static let minimumGridWidth: CGFloat = 340 * 2 + 16 + 40

    private let minimumColumnWidth: CGFloat = 340
    private let spacing: CGFloat = 16

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let width = proposal.width ?? minimumColumnWidth
        let metrics = rowMetrics(width: width, subviews: subviews)
        return CGSize(width: width, height: metrics.heights.reduce(0, +) + CGFloat(metrics.heights.count - 1) * spacing)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }

        let columns = columnCount(for: bounds.width)
        let metrics = rowMetrics(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in metrics.heights.enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (metrics.width + spacing), y: y),
                    anchor: .topLeading,
                    proposal: .init(width: metrics.width, height: height)
                )
            }
            y += height + spacing
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        width >= minimumColumnWidth * 2 + spacing ? 2 : 1
    }

    private func rowMetrics(width: CGFloat, subviews: Subviews) -> (width: CGFloat, heights: [CGFloat]) {
        let columns = columnCount(for: width)
        let cardWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        // Only neighbors share a height; taller content in another row must not
        // add empty space to the overview or the category stack.
        let heights = stride(from: 0, to: subviews.count, by: columns).map { start in
            (start..<min(start + columns, subviews.count)).map {
                subviews[$0].sizeThatFits(.init(width: cardWidth, height: nil)).height
            }.max() ?? 0
        }
        return (cardWidth, heights)
    }
}

#Preview {
    DashboardView()
        .environmentInjection()
}

#Preview("Empty State") {
    DashboardView()
        .environmentInjection(empty: true)
}
