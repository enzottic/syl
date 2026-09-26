import SwiftUI

struct MonthPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var month: Int
    @State private var year: Int

    let allowsFutureMonths: Bool
    let onSelect: (Date) -> Void
    private let calendar = Calendar.current

    init(month: Date, allowsFutureMonths: Bool = false, onSelect: @escaping (Date) -> Void) {
        _month = State(initialValue: Calendar.current.component(.month, from: month))
        _year = State(initialValue: Calendar.current.component(.year, from: month))
        self.allowsFutureMonths = allowsFutureMonths
        self.onSelect = onSelect
    }

    private var selectedDate: Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    private var years: ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: Date())
        let lastYear = allowsFutureMonths ? max(currentYear, year) + 100 : currentYear
        return min(1900, year)...lastYear
    }

    var body: some View {
        NavigationStack {
            HStack {
                Picker("Month", selection: $month) {
                    ForEach(1...12, id: \.self) { index in
                        Text(calendar.monthSymbols[index - 1]).tag(index)
                    }
                }
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
            }
            .pickerStyle(.wheel)
            .padding()
            .navigationTitle("Choose Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSelect(selectedDate)
                        dismiss()
                    }
                    .disabled(!allowsFutureMonths && selectedDate > Date())
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("This Month") {
                        onSelect(calendar.dateInterval(of: .month, for: Date())!.start)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
