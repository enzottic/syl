import Testing

@Suite("Dashboard widget order")
@MainActor
struct DashboardWidgetOrderTests {
    @Test
    func repairsSavedOrderWithoutLosingUserPositions() {
        let saved = ["recentExpenses", "removedWidget", "needs", "recentExpenses", "savings"]
        let resolved = DashboardWidgetID.resolvedOrder(saved, defaultOrder: DashboardWidgetID.defaultOrder(isPad: false))
        #expect(resolved == [.recentExpenses, .categories, .monthlyOverview,
                             .expenseCalendar, .mostSpentTags, .upcomingRecurring])
        #expect(Set(resolved) == Set(DashboardWidgetID.allCases))
    }

    @Test(arguments: ["needs", "wants", "savings"])
    func mergesLegacyCategoriesAtTheirFirstPosition(first: String) {
        let saved = ["expenseCalendar", first, "monthlyOverview", "needs", "wants", "savings", "categories"]
        let resolved = DashboardWidgetID.resolvedOrder(saved)
        #expect(Array(resolved.prefix(3)) == [.expenseCalendar, .categories, .monthlyOverview])
        #expect(resolved.filter { $0 == .categories }.count == 1)
        #expect(DashboardWidgetID.resolvedOrder(resolved.map(\.rawValue)) == resolved)
    }

    @Test(arguments: [false, true])
    func missingOrObsoletePreferencesUseDeviceDefault(isPad: Bool) {
        #expect(DashboardWidgetID.resolvedOrder([], defaultOrder: DashboardWidgetID.defaultOrder(isPad: isPad)) == DashboardWidgetID.defaultOrder(isPad: isPad))
        #expect(DashboardWidgetID.resolvedOrder(["obsolete"], defaultOrder: DashboardWidgetID.defaultOrder(isPad: isPad)) == DashboardWidgetID.defaultOrder(isPad: isPad))
    }
}
