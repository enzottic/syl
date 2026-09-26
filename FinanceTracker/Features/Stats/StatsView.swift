import SwiftUI
import SwiftData
import Charts
import SageKit



struct StatsView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.categoryColors) private var categoryColors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @AppStorage("statsShowsNeedsLine") private var showsNeedsLine = true
    @AppStorage("statsShowsWantsLine") private var showsWantsLine = true
    @AppStorage("statsShowsSavingsLine") private var showsSavingsLine = true
    
    @State private var selectedMonth = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var timeframe: StatsTimeframe = .monthly
    @State private var selectedCategory: ExpenseCategory?
    @State private var selectedTag: ExpenseTag?
    @State private var selectedBar: String?
    @State private var showsMonthPicker = false
    @State private var chartHover: ChartSelection?
    @State private var dailyOverviewHeight: CGFloat = 220
    @State private var statsViewport: CGRect = .zero
    @GestureState private var chartTouch: ChartSelection?
    
    private var chartSelection: ChartSelection? { chartTouch ?? chartHover }
    private var selectedDay: Int? { chartSelection?.day }
    private var visibleCategories: [ExpenseCategory] {
        ExpenseCategory.allCases.filter { category in
            switch category {
            case .needs: showsNeedsLine
            case .wants: showsWantsLine
            case .savings: showsSavingsLine
            @unknown default: false
            }
        }
    }

    private let calendar = Calendar.current
    private var currentMonth: Date { calendar.dateInterval(of: .month, for: Date())!.start }
    private var isCurrentMonth: Bool { selectedMonth == currentMonth }
    private var accentColor: Color {
        if let category = selectedCategory { return category.color(in: categoryColors) }
        if let tag = selectedTag, !tag.isDeleted { return tag.color }
        return .sage
    }

    /// Fades for filter changes. Month changes keep their own, longer morph on the chart.
    /// A bounce-free spring: starts promptly and settles with a long, soft deceleration.
    private var filterAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.45) }

    /// Every category budget, visible only for the filtered category. They are always passed
    /// so switching categories cross-fades between budget lines. Skipped when no income is set.
    private var chartBudgets: [DailySpendingChart.Budget] {
        ExpenseCategory.allCases.compactMap { category in
            let amount: Double = switch category {
            case .needs: config.needsBudget
            case .wants: config.wantsBudget
            case .savings: config.savingsBudget
            @unknown default: 0
            }
            guard amount > 0 else { return nil }
            return .init(id: category.rawValue, amount: amount, color: category.color(in: categoryColors),
                         isVisible: category == selectedCategory)
        }
    }

    private func tagFilteredExpenses(from expenses: [Expense]) -> [Expense] {
        guard let selectedTag, !selectedTag.isDeleted else { return expenses }
        return expenses.filter { ($0.tags ?? []).contains { $0.id == selectedTag.id } }
    }

    private func filteredExpenses(from expenses: [Expense]) -> [Expense] {
        let tagged = tagFilteredExpenses(from: expenses)
        guard let selectedCategory else { return tagged }
        return tagged.filter { $0.category == selectedCategory }
    }
    
    private var daysInMonth: Int { calendar.range(of: .day, in: .month, for: selectedMonth)!.count }

    private func chartData(for expenses: [Expense]) -> [SpendingPeriodData] {
        let now = Date()
        
        if timeframe == .monthly {
            // Keep the recent window stable when selecting its bars. Older months get their own window.
            let earliestRecent = calendar.date(byAdding: .month, value: -5, to: currentMonth)!
            let end = selectedMonth < earliestRecent ? selectedMonth : currentMonth
            return (0..<6).reversed().map { offset in
                let start = calendar.date(byAdding: .month, value: -offset, to: end)!
                let interval = calendar.dateInterval(of: .month, for: start)!
                let total = expenses.filter { $0.date >= start && $0.date < interval.end && $0.date <= now }.total
                return SpendingPeriodData(periodStart: start, label: start.formatted(.dateTime.month(.abbreviated)), total: total)
            }
        }
        
        let month = calendar.dateInterval(of: .month, for: selectedMonth)!
        var start = month.start
        var result: [SpendingPeriodData] = []
        while start < month.end {
            let week = calendar.dateInterval(of: .weekOfYear, for: start)!
            let end = min(week.end, month.end)
            let lastDay = calendar.component(.day, from: calendar.date(byAdding: .day, value: -1, to: end)!)
            let label = "\(calendar.component(.day, from: start))–\(lastDay)"
            let total = expenses.filter { $0.date >= start && $0.date < end && $0.date <= now }.total
            result.append(SpendingPeriodData(periodStart: start, label: label, total: total))
            start = end
        }
        return result
    }

    var body: some View {
        StatsExpenseHistory(selectedMonth: selectedMonth, currentMonth: currentMonth,
                            category: selectedCategory,
                            tagID: selectedTag?.isDeleted == true ? nil : selectedTag?.id) { expenses, firstRecordedDate in
            let tagged = tagFilteredExpenses(from: expenses)
            let filtered = filteredExpenses(from: expenses)
            let monthSummary = SpendingMonthSummary(month: selectedMonth, expenses: filtered,
                                                    firstRecordedDate: firstRecordedDate)
            let periods = chartData(for: filtered)

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // The chip row's 44pt tap target already pads the capsule, so keep the gap tight.
                        VStack(alignment: .leading, spacing: 4) {
                            StatsActiveFilters(selectedCategory: $selectedCategory, selectedTag: $selectedTag)
                            monthlyChart(monthSummary, tagFiltered: tagged)
                        }
                        // Lift the group too, so the chart's day overview draws above the cards below.
                        .zIndex(chartSelection == nil ? 0 : 1)

                        InsightsCard(summary: monthSummary, isCurrentMonth: isCurrentMonth)

                        if selectedTag == nil || selectedTag?.isDeleted == true {
                            topTags(monthSummary)
                        }

                        historyChart(periods: periods)
                    }
                    .padding()
                }
                .accessibilityIdentifier("stats-scroll-view")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { statsViewport = $0 }
                .background(.sageBackground)
                .navigationTitle("Stats")
                .navigationSubtitle(selectedMonth.formatted(.dateTime.month(.wide).year()))
                .gradientBackground(color: accentColor)
                .toolbar { statsToolbar }
                .onChange(of: selectedBar) { _, label in
                    if timeframe == .monthly, let item = periods.first(where: { $0.label == label }) {
                        selectedMonth = item.periodStart
                        selectedBar = nil
                    }
                }
                .onChange(of: selectedMonth) { chartHover = nil }
                .sheet(isPresented: $showsMonthPicker) {
                    MonthPicker(month: selectedMonth) { selectedMonth = $0 }
                }
                .onDisappear { chartHover = nil }
            }
        }
    }

    private func changeMonth(by offset: Int) {
        selectedMonth = min(calendar.date(byAdding: .month, value: offset, to: selectedMonth)!, currentMonth)
    }

    /// The legend and chart lines share the toolbar's category filter. Selecting the active
    /// category, or Total, clears it.
    private func selectCategory(_ category: ExpenseCategory?) {
        withAnimation(filterAnimation) {
            selectedCategory = selectedCategory == category ? nil : category
        }
    }

    @ToolbarContentBuilder
    private var statsToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { changeMonth(by: -1) } label: { Label("Previous Month", systemImage: "chevron.left") }
                .accessibilityIdentifier("stats-previous-month")
            Button { changeMonth(by: 1) } label: { Label("Next Month", systemImage: "chevron.right") }
                .disabled(isCurrentMonth)
                .accessibilityIdentifier("stats-next-month")
        }
        
        ToolbarItemGroup(placement: .topBarTrailing) {
            StatsFilterMenu(selectedCategory: $selectedCategory, selectedTag: $selectedTag,
                            showsMonthPicker: $showsMonthPicker)
            Menu {
                Section("Category Lines") {
                    Toggle("Needs", isOn: $showsNeedsLine)
                    Toggle("Wants", isOn: $showsWantsLine)
                    Toggle("Savings", isOn: $showsSavingsLine)
                }
            } label: {
                Label("Chart Options", systemImage: "ellipsis")
            }
            .menuActionDismissBehavior(.disabled)
            .accessibilityIdentifier("stats-chart-options")
        }
    }

    private func monthlyChart(_ summary: SpendingMonthSummary, tagFiltered: [Expense]) -> some View {
        // Every line is always drawn, from data that ignores the category filter, so lines that
        // a filter hides keep their shape and fade out in place. The filtered category's own line
        // matches the filtered summary exactly.
        let lineSummary = selectedCategory == nil ? summary
            : SpendingMonthSummary(month: selectedMonth, expenses: tagFiltered)
        let chartSeries = [SpendingChartSeries(category: nil, points: lineSummary.days, color: .primary,
                                               isVisible: selectedCategory == nil)] +
            ExpenseCategory.allCases.map { category in
                SpendingChartSeries(category: category, points: lineSummary.categoryDays[category] ?? [],
                                    color: category.color(in: categoryColors),
                                    isVisible: selectedCategory.map { $0 == category } ?? visibleCategories.contains(category))
            }
        let visibleSeries = chartSeries.filter(\.isVisible)
        // Keep the filtered category in the legend even if its line is hidden in Chart Options.
        let legendCategories = ExpenseCategory.allCases.filter { visibleCategories.contains($0) || $0 == selectedCategory }

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.total.currencyString(code: config.ledgerCurrencyCode))
                    .font(.largeTitle.bold()).monospacedDigit().textSelection(.enabled)
                    .accessibilityIdentifier("stats-month-total")
                Text(isCurrentMonth ? "Spent so far" : "Total spent")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            
            DailySpendingChart(series: chartSeries,
                               averageDays: summary.averageDays,
                               daysInMonth: daysInMonth, currencyCode: config.ledgerCurrencyCode,
                               selectedDay: selectedDay,
                               budgets: chartBudgets)
                .chartYScale(domain: 0...Double(max(config.totalMonthlyIncome, 1)))
                .chartPlotStyle { plot in plot.clipped() }
                // Month changes morph every line to new data; filter changes mostly fade lines
                // in and out, and get a slightly longer settle so the fade eases to rest.
                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: selectedMonth)
                .animation(filterAnimation, value: selectedCategory)
                .animation(filterAnimation, value: selectedTag?.id)
                .animation(filterAnimation, value: visibleCategories)
                .chartOverlay { proxy in
                    chartInteractionOverlay(summary, proxy: proxy, series: visibleSeries)
                }
                .frame(height: 200)
                .accessibilityIdentifier("stats-daily-chart")
            
            HStack(spacing: 8) {
                legendButton(category: nil, color: .primary)
                ForEach(legendCategories, id: \.self) { category in
                    legendButton(category: category, color: category.color(in: categoryColors))
                }
                
                if summary.historicalMonthCount > 0 {
                    HStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Capsule().frame(width: 4, height: 2)
                            Capsule().frame(width: 4, height: 2)
                        }
                        Text("Average")
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Average cumulative spending by calendar day. Shorter months carry their final total forward.")
                }
            }
        }
        .padding(16)
        .background(.cardBackground, in: .rect(cornerRadius: 15))
        .coordinateSpace(name: "stats-chart-card")
        .overlay {
            GeometryReader { geometry in
                if let chartSelection {
                    let cardFrame = geometry.frame(in: .global)
                    let visibleFrame = statsViewport.isEmpty ? cardFrame : statsViewport
                    let bounds = CGRect(x: 0, y: visibleFrame.minY - cardFrame.minY,
                                        width: geometry.size.width, height: visibleFrame.height)
                    dailyOverview(summary, day: chartSelection.day, category: selectedCategory,
                                  finger: chartSelection.location, highestLineY: chartSelection.highestLineY, bounds: bounds)
                }
            }
            .allowsHitTesting(false)
        }
        .zIndex(chartSelection == nil ? 0 : 1)
    }

    private func legendButton(category: ExpenseCategory?, color: Color) -> some View {
        let isSelected = selectedCategory == category && category != nil
        return Button { selectCategory(category) } label: {
            HStack(spacing: 4) {
                Capsule().fill(color).frame(width: 10, height: 3)
                Text(category?.rawValue ?? "Total")
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.caption)
            .foregroundStyle(selectedCategory == nil || isSelected ? Color.primary : .secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected || category == nil ? "Show all categories" : "Filter by this category")
    }

    private func chartInteractionOverlay(_ summary: SpendingMonthSummary, proxy: ChartProxy,
                                         series: [SpendingChartSeries]) -> some View {
        GeometryReader { geometry in
            if let plotFrame = proxy.plotFrame {
                let frame = geometry[plotFrame]
                let selectionAt: (CGPoint) -> ChartSelection? = { location in
                    guard let lastDay = summary.days.last?.day,
                          let chartDay = proxy.value(atX: min(max(location.x, 0), frame.width), as: Double.self)
                    else { return nil }
                    // Touch and hover coordinates are local to the plot, not the chart axes.
                    let chartOrigin = geometry.frame(in: .named("stats-chart-card")).origin
                    let points = series.flatMap(\.points) + summary.averageDays
                    let highestLineY = points.compactMap { proxy.position(forY: $0.total) }.min() ?? 0
                    return ChartSelection(
                        day: min(max(Int(chartDay.rounded()), 1), lastDay),
                        location: CGPoint(x: chartOrigin.x + frame.minX + location.x,
                                          y: chartOrigin.y + frame.minY + location.y),
                        highestLineY: chartOrigin.y + frame.minY + highestLineY
                    )
                }
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(width: frame.width, height: frame.height)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.25)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .updating($chartTouch) { value, touch, _ in
                                guard case let .second(true, drag?) = value else { return }
                                touch = selectionAt(drag.location)
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { value in
                            selectLine(at: value.location, proxy: proxy, series: series)
                        }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            chartHover = selectionAt(location)
                        case .ended:
                            chartHover = nil
                        }
                    }
                    .position(x: frame.midX, y: frame.midY)
            }
        }
    }

    private func dailyOverview(_ summary: SpendingMonthSummary, day: Int, category: ExpenseCategory?,
                               finger: CGPoint, highestLineY: CGFloat, bounds: CGRect) -> some View {
        let inset: CGFloat = 8
        let gap: CGFloat = 16
        let width = min(260, bounds.width - inset * 2)
        let height = dailyOverviewHeight
        let x = min(max(finger.x, inset + width / 2), bounds.width - inset - width / 2)
        // Anchor to the highest visible line, never the finger's vertical position.
        // Keep the overview readable at the top edge rather than flipping below the chart.
        let y = max(bounds.minY + inset + height / 2, highestLineY - gap - height / 2)

        return dailySpendingDetails(summary, day: day, category: category)
            .padding(12)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dailyOverviewHeight = $0 }
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.1))
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .position(x: x, y: y)
    }

    private func selectLine(at location: CGPoint, proxy: ChartProxy, series: [SpendingChartSeries]) {
        // Hit-test the rendered segments, so taps between calendar days still select the line.
        var closest: (category: ExpenseCategory?, distance: CGFloat)?
        for line in series {
            let positions = line.points.compactMap { point -> CGPoint? in
                guard let x = proxy.position(forX: point.day), let y = proxy.position(forY: point.total) else { return nil }
                return CGPoint(x: x, y: y)
            }
            for (index, start) in positions.enumerated() {
                let end = positions[min(index + 1, positions.count - 1)]
                let dx = end.x - start.x
                let dy = end.y - start.y
                let lengthSquared = dx * dx + dy * dy
                let fraction = lengthSquared == 0 ? 0 : min(max(((location.x - start.x) * dx + (location.y - start.y) * dy) / lengthSquared, 0), 1)
                let distance = hypot(location.x - start.x - fraction * dx, location.y - start.y - fraction * dy)
                if distance <= 22, closest == nil || distance <= closest!.distance {
                    closest = (line.category, distance)
                }
            }
        }
        if let closest {
            selectCategory(closest.category)
        }
    }

    private func dailySpendingDetails(_ summary: SpendingMonthSummary, day: Int, category: ExpenseCategory?) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: selectedMonth)!
        let expenses = summary.expenses.filter {
            calendar.isDate($0.date, inSameDayAs: date) && (category == nil || $0.category == category)
        }
            .sorted { $0.amount == $1.amount ? $0.date > $1.date : $0.amount > $1.amount }

        return DailySpendingDetails(date: date, total: expenses.total, expenses: expenses,
                                    category: category, style: .topExpenses,
                                    accessibilityPrefix: "stats-day")
    }

    private func topTags(_ summary: SpendingMonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Tags").font(.headline)
            if summary.expenses.contains(where: { ($0.tags ?? []).contains { !$0.isDeleted } }) {
                TopSpendingBreakdown(expenses: summary.expenses, accentColor: accentColor,
                                     includesUntaggedExpenses: false, showsCardBackground: false)
            } else {
                Text("Add some expenses to see your top used tags")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.cardBackground, in: .rect(cornerRadius: 15))
    }

    private func historyChart(periods: [SpendingPeriodData]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            
            Text("Spending History").font(.headline)
            
            Picker("Breakdown", selection: $timeframe) {
                ForEach(StatsTimeframe.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            
            Chart(periods) { item in
                BarMark(x: .value("Period", item.label), y: .value("Spent", item.total))
                    .foregroundStyle(timeframe == .weekly || item.periodStart == selectedMonth ? accentColor : accentColor.opacity(0.35))
                    .cornerRadius(4)
                    .accessibilityLabel(timeframe == .monthly ? item.periodStart.formatted(.dateTime.month(.wide).year()) : "Days \(item.label)")
                    .accessibilityValue(item.total.currencyString(code: config.ledgerCurrencyCode))
            }
            .chartXSelection(value: $selectedBar)
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { value in
                    guard timeframe == .monthly else { return }
                    proxy.selectXValue(at: value.location.x)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel { if let amount = value.as(Double.self) { Text(amount.currencyStringRounded(code: config.ledgerCurrencyCode)).font(.caption2) } }
                }
            }
            .frame(height: 180)
            .accessibilityRepresentation {
                ForEach(periods) { item in
                    if timeframe == .monthly {
                        Button { selectedMonth = item.periodStart } label: {
                            Text("\(item.periodStart.formatted(.dateTime.month(.wide).year())), \(item.total.currencyString(code: config.ledgerCurrencyCode))")
                        }
                    } else {
                        Text("Days \(item.label), \(item.total.currencyString(code: config.ledgerCurrencyCode))")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stats-history-chart")
            
        }
        .padding(16)
        .background(.cardBackground, in: .rect(cornerRadius: 15))
    }
}

extension StatsView {
    struct ChartSelection {
        let day: Int
        let location: CGPoint
        let highestLineY: CGFloat
    }
    
    enum StatsTimeframe: String, CaseIterable, Identifiable {
        case monthly = "Monthly"
        case weekly = "Weekly"
        var id: String { rawValue }
    }

    private struct SpendingPeriodData: Identifiable {
        let periodStart: Date
        let label: String
        let total: Double
        var id: Date { periodStart }
    }
}

#Preview { StatsView().environmentInjection() }
