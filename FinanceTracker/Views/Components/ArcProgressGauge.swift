//
//  ArcProgressGauge.swift
//  FinanceTracker
//
//  Created by Enzo on 7/14/26.
//

import SwiftUI

struct ArcProgressGauge<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double
    var tint: Color = .sage
    var lineWidthRatio: CGFloat = 0.073
    var lineWidthRange: ClosedRange<CGFloat> = 16...30
    @ViewBuilder var content: () -> Content

    private var clampedProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            let lineWidth = (proxy.size.width * lineWidthRatio)
                .clamped(to: lineWidthRange)
            let markerDiameter = (lineWidth * 1.75).clamped(to: 38...48)
            let arcInset = max(lineWidth / 2, markerDiameter / 2)

            ZStack(alignment: .bottom) {
                ArcShape(inset: arcInset)
                    .stroke(tint.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                ArcShape(inset: arcInset)
                    .trim(from: 0, to: clampedProgress)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .animation(reduceMotion ? nil : .dashboardProgress, value: clampedProgress)

                content()
                    .padding(.horizontal, lineWidth)
                    .frame(width: proxy.size.width, height: max(0, proxy.size.height - lineWidth / 2), alignment: .center)
                    .offset(y: lineWidth / 4)

                ArcProgressMarker(
                    progress: progress,
                    tint: tint,
                    diameter: markerDiameter,
                    gaugeSize: proxy.size,
                    arcInset: arcInset
                )
                    .animation(reduceMotion ? nil : .dashboardProgress, value: progress)
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(clampedProgress, format: .percent.precision(.fractionLength(0))))
    }

}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private struct ArcShape: Shape {
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = max(min(rect.width / 2, rect.height) - inset, 0)
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY - inset),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        return path
    }
}

private struct ArcProgressMarker: View, Animatable {
    @Environment(\.self) private var environment

    var progress: Double
    let tint: Color
    let diameter: CGFloat
    let gaugeSize: CGSize
    let arcInset: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Text(progress, format: .percent.precision(.fractionLength(0)))
            .font(.caption2.bold())
            .foregroundStyle(tint.legibleForeground(in: environment))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: diameter, height: diameter)
            .background(tint, in: Circle())
            .overlay {
                Circle()
                    .stroke(.background, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
            .position(tip)
    }

    private var tip: CGPoint {
        let clampedProgress = min(max(progress, 0), 1)
        let radius = max(min(gaugeSize.width / 2, gaugeSize.height) - arcInset, 0)
        let angle = Angle.degrees(180 + (180 * clampedProgress)).radians

        return CGPoint(
            x: gaugeSize.width / 2 + radius * cos(angle),
            y: gaugeSize.height - arcInset + radius * sin(angle)
        )
    }
}

#Preview {
    VStack(spacing: 32) {
        ArcProgressGauge(progress: 0.44) {
            Text(0.44, format: .percent.precision(.fractionLength(0)))
                .font(.largeTitle)
                .fontWeight(.bold)
        }

        ArcProgressGauge(progress: 1, tint: .red) {
            Text("Over")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
    .padding()
}
