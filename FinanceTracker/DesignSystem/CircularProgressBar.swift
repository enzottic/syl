//
//  CircularProgressBar.swift
//  FinanceTracker
//
//  Created by Enzo on 12/24/25.
//

import SwiftUI
import Charts

struct CircularProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double
    let lineWidth: CGFloat
    let tint: Color

    private var clampedProgress: Double { min(max(progress, 0), 1) }
    
    init(progress: Double, tint: Color = .blue, lineWidth: CGFloat = 5) {
        self.progress = progress
        self.tint = tint
        self.lineWidth = lineWidth
    }
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: lineWidth)
            
            // Progress circle
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90)) // Start from top
                .animation(reduceMotion ? nil : .dashboardProgress, value: clampedProgress)
            
            Text(clampedProgress.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Budget used")
        .accessibilityValue(Text(clampedProgress, format: .percent.precision(.fractionLength(0))))
    }
}




#Preview {
    CircularProgressBar(progress: 0.7)
}
