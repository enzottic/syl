import SwiftUI
import SageKit

struct BudgetAllocationBar: View {
    @Environment(\.categoryColors) private var categoryColors
    @ScaledMetric(relativeTo: .title2) private var barHeight = 156
    @Binding var needsPercent: Double
    @Binding var wantsPercent: Double
    @State private var dragStart: Double?
    @GestureState private var isDragging = false

    private var secondBoundary: Double { needsPercent + wantsPercent }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    segment("Needs", percentage: needsPercent, color: categoryColors.needs,
                            width: geometry.size.width * needsPercent / 100)
                    segment("Wants", percentage: wantsPercent, color: categoryColors.wants,
                            width: geometry.size.width * wantsPercent / 100)
                    segment("Savings", percentage: 100 - secondBoundary, color: categoryColors.savings,
                            width: geometry.size.width * (100 - secondBoundary) / 100)
                }
                .background(Color.cardBackground)
                .clipShape(.rect(cornerRadius: 24))
                .accessibilityHidden(true)

                divider(first: true, width: geometry.size.width)
                divider(first: false, width: geometry.size.width)
            }
        }
        .frame(height: barHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-allocation-bar")
        .sensoryFeedback(.selection, trigger: needsPercent)
        .sensoryFeedback(.selection, trigger: secondBoundary)
        .onChange(of: isDragging) { _, dragging in
            if !dragging { dragStart = nil }
        }
    }

    private func segment(_ title: LocalizedStringKey, percentage: Double, color: Color, width: CGFloat) -> some View {
        color.opacity(0.3)
            .frame(width: max(0, width), height: barHeight)
            .overlay {
                if width >= 64 {
                    VStack(spacing: 8) {
                        Text(title).font(.caption.weight(.semibold))
                        Text(percentage / 100, format: .percent.precision(.fractionLength(0)))
                            .font(.title2.bold())
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 4)
                } else if width > 0 {
                    // Rotate narrow labels rather than squeezing them into unreadable text.
                    HStack(spacing: 4) {
                        Text(title)
                        Text(percentage / 100, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .font(.caption2.weight(.semibold))
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                }
            }
            .clipped()
    }

    private func divider(first: Bool, width: CGFloat) -> some View {
        let boundary = first ? needsPercent : secondBoundary
        // Keep the full grab targets inside the bar, including at 0% and 100%.
        let firstX = min(max(width * needsPercent / 100, 22), width - 22)
        let secondX = min(max(width * secondBoundary / 100, 22), width - 22)
        // Separate the grab targets when Wants is narrow or zero so both remain reachable.
        let crowded = secondX - firstX < 44
        let targetHeight = crowded ? barHeight / 2 : barHeight
        let y = crowded ? barHeight * (first ? 0.25 : 0.75) : barHeight / 2

        return ZStack {
            Rectangle()
                .fill(Color.primary.opacity(0.25))
                .frame(width: 2, height: barHeight)
                .position(x: width * boundary / 100, y: barHeight / 2)
                .allowsHitTesting(false)

            Image(systemName: "chevron.compact.left")
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.compact.right").offset(x: 6)
                }
                .font(.caption.bold())
                .foregroundStyle(.primary)
                .offset(x: -3)
                .frame(width: 24, height: 40)
                .background(Color.cardBackground, in: .capsule)
                .overlay { Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1) }
                .frame(width: 44, height: targetHeight)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .updating($isDragging) { _, state, _ in state = true }
                        .onChanged { value in
                            guard width > 0 else { return }
                            if dragStart == nil { dragStart = boundary }
                            updateBoundary((dragStart ?? boundary) + value.translation.width / width * 100, first: first)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(first ? "Needs and Wants divider" : "Wants and Savings divider")
                .accessibilityValue(first
                    ? "Needs \((needsPercent / 100).formatted(.percent.precision(.fractionLength(0)))), Wants \((wantsPercent / 100).formatted(.percent.precision(.fractionLength(0))))"
                    : "Wants \((wantsPercent / 100).formatted(.percent.precision(.fractionLength(0)))), Savings \(((100 - secondBoundary) / 100).formatted(.percent.precision(.fractionLength(0))))")
                .accessibilityHint("Swipe up or down to move the divider in five percent steps")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: updateBoundary(boundary + 5, first: first)
                    case .decrement: updateBoundary(boundary - 5, first: first)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier(first ? "onboarding-needs-divider" : "onboarding-savings-divider")
                .position(x: first ? firstX : secondX, y: y)
        }
    }

    private func updateBoundary(_ percentage: Double, first: Bool) {
        let snapped = (percentage / 5).rounded() * 5
        if first {
            let total = secondBoundary
            let needs = min(max(snapped, 0), total)
            needsPercent = needs
            wantsPercent = total - needs
        } else {
            wantsPercent = min(max(snapped, needsPercent), 100) - needsPercent
        }
    }
}
