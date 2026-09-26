import SwiftUI

struct DashboardWidgetOrderSheet: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.dismiss) private var dismiss
    @State private var orderBeforeReset: [DashboardWidgetID]?

    private var order: [DashboardWidgetID] { config.dashboardWidgetOrder }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { widget in
                        Label {
                            Text(widget.title)
                        } icon: {
                            Image(systemName: widget.symbol)
                                .foregroundStyle(.sageTint)
                        }
                        .frame(minHeight: 28)
                        .accessibilityIdentifier("widget-order-\(widget.rawValue)")
                        .accessibilityActions {
                            if widget != order.first {
                                Button("Move Up") { move(widget, by: -1) }
                            }
                            if widget != order.last {
                                Button("Move Down") { move(widget, by: 1) }
                            }
                        }
                        .contextMenu {
                            Button("Move Up", systemImage: "arrow.up") { move(widget, by: -1) }
                                .disabled(widget == order.first)
                            Button("Move Down", systemImage: "arrow.down") { move(widget, by: 1) }
                                .disabled(widget == order.last)
                        }
                    }
                    .onMove { source, destination in
                        var updated = order
                        updated.move(fromOffsets: source, toOffset: destination)
                        config.dashboardWidgetOrder = updated
                        orderBeforeReset = nil
                    }
                }
                Section {
                    Button("Reset to Default") {
                        orderBeforeReset = order
                        config.dashboardWidgetOrder = DashboardWidgetID.defaultOrder
                    }
                    .disabled(order == DashboardWidgetID.defaultOrder)
                    if let previous = orderBeforeReset {
                        Button("Undo Reset") {
                            config.dashboardWidgetOrder = previous
                            orderBeforeReset = nil
                        }
                    }
                }
                .moveDisabled(true)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Widgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(.sageTint)
        .presentationSizing(.form)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func move(_ widget: DashboardWidgetID, by offset: Int) {
        guard let index = order.firstIndex(of: widget), order.indices.contains(index + offset) else { return }
        var updated = order
        updated.swapAt(index, index + offset)
        config.dashboardWidgetOrder = updated
        orderBeforeReset = nil
    }
}
