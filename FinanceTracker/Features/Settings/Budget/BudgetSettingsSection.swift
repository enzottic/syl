//
//  BudgetSettingsSection.swift
//  FinanceTracker
//
//  Created by Enzo on 5/18/26.
//

import SwiftUI
import WidgetKit
import SageKit

struct BudgetSettingsSection: View {
    @Environment(AppConfiguration.self) private var config

    @FocusState private var needsFocus: Bool
    @State private var pendingCurrencyCode: String?

    var body: some View {
        @Bindable var config = config
        List {
            Section {
                Picker("Ledger Currency", selection: Binding(
                    get: { config.ledgerCurrencyCode },
                    set: { code in
                        guard code != config.ledgerCurrencyCode else { return }
                        needsFocus = false
                        pendingCurrencyCode = code
                    }
                )) {
                    ForEach(LedgerCurrency.supportedCodes, id: \.self) { code in
                        Text("\(code) - \(Locale.current.localizedString(forCurrencyCode: code) ?? code)")
                            .tag(code)
                            .accessibilityIdentifier("ledger-currency-\(code)")
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("ledger-currency-picker")
                .accessibilityValue(config.ledgerCurrencyCode)
            } footer: {
                Text("This currency is used for existing and future expenses, income, budgets, and recurring expenses. Changing it leaves all amounts unchanged, with no conversion, and applies to your other synced devices.")
            }
            Section {
                WholeNumberCurrencyField(amount: $config.totalMonthlyIncome, isFocused: $needsFocus)
                    .onChange(of: config.totalMonthlyIncome) { oldValue, newValue in
                        WidgetCenter.shared.reloadAllTimelines()
                    }
            } header: {
                Text("Monthly Income")
            }
            
            Section {
                    AllocationSlider(
                        title: "Wants",
                        color: .want,
                        icon: "cart.fill",
                        percentage: Binding(
                            get: { config.wantsPercent * 100 },
                            set: { config.updateWants($0 / 100) }
                        )
                    )

                    AllocationSlider(
                        title: "Needs",
                        color: .need,
                        icon: "house.fill",
                        percentage: Binding(
                            get: { config.needsPercent * 100 },
                            set: { config.updateNeeds($0 / 100) }
                        )
                    )

                    HStack {
                        Image(systemName: "banknote.fill")
                            .foregroundStyle(.teal)
                            .frame(width: 30)

                        Text("Savings")
                            .font(.headline)

                        Spacer()

                        Text(config.savingsPercent, format: .percent.precision(.fractionLength(0)))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                    }
            } header: {
                Text("Budget Allocation")
            }
        }
        .settingsBackground()
        .navigationTitle("Budget and Allocation")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Change Ledger Currency?", isPresented: Binding(
            get: { pendingCurrencyCode != nil },
            set: { if !$0 { pendingCurrencyCode = nil } }
        ), presenting: pendingCurrencyCode) { code in
            Button("Change Currency") {
                config.ledgerCurrencyCode = code
                pendingCurrencyCode = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCurrencyCode = nil
            }
        } message: { code in
            Text("Use \(code) for existing and future expenses, income, budgets, and recurring expenses? All amounts stay unchanged. No currency conversion is performed.")
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button("Done") {
                    needsFocus = false
                }
            }
        }
    }
}

#Preview {
    BudgetSettingsSection()
        .environment(AppConfiguration.preview)
        .fontDesign(.rounded)
}
