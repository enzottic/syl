//
//  WholeNumberCurrencyField.swift
//  FinanceTracker
//
//  Created by Enzo on 3/13/26.
//

import SwiftUI
import SageKit

struct WholeNumberCurrencyField: View {
    @Environment(AppConfiguration.self) private var config
    @Binding var amount: Int
    var isFocused: FocusState<Bool>.Binding
    @State private var rawValue: String = "0"

    private var displayValue: String {
        let value = Int(rawValue) ?? 0

        return value.currencyString(code: config.ledgerCurrencyCode)
    }

    var body: some View {
        ZStack {
            TextField("", text: $rawValue)
                .keyboardType(.numberPad)
                .opacity(0)
                .frame(width: 0, height: 0)
                .focused(isFocused)
                .onChange(of: rawValue) { oldValue, newValue in
                    let filtered = newValue.filter { $0.isNumber }

                    if filtered.isEmpty {
                        rawValue = "0"
                        amount = 0
                    } else if filtered.count > 8 { // Max $99,999,999
                        rawValue = String(filtered.prefix(8))
                    } else {
                        rawValue = filtered
                    }

                    amount = Int(rawValue) ?? 0
                }

            Text(displayValue)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(isFocused.wrappedValue ? .primary : .secondary)
                .onTapGesture {
                    isFocused.wrappedValue = true
                }
        }
        .onAppear {
            if amount > 0 {
                rawValue = String(amount)
            }
        }
    }
}

#Preview {
    @Previewable @State var amount: Int = 0
    @Previewable @FocusState var isFocused: Bool

    VStack(spacing: 30) {
        WholeNumberCurrencyField(amount: $amount, isFocused: $isFocused)

        Text("Current amount: \(amount)")
            .foregroundStyle(.secondary)

        Button("Clear") {
            amount = 0
        }
    }
    .padding()
    .environment(AppConfiguration.preview)
}
