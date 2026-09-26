//
//  AllocationSlider.swift
//  FinanceTracker
//
//  Created by Enzo on 10/21/25.
//

import SwiftUI

struct AllocationSlider: View {
    let title: String
    let color: Color
    let icon: String
    @Binding var percentage: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 30)

                Text(title)
                    .font(.headline)

                Spacer()

                Text(percentage / 100, format: .percent.precision(.fractionLength(0)))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
            }

            Slider(value: Binding(
                get: { percentage },
                set: { newValue in
                    percentage = round(newValue / 5) * 5
                }
            ), in: 0...100, step: 5)
                .tint(color)
                .accessibilityLabel(title)
                .accessibilityValue(Text(percentage / 100, format: .percent.precision(.fractionLength(0))))
                .accessibilityHint("Adjusts in five percent steps")
        }
        .onChange(of: percentage) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
