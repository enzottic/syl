//
//  TagCapsule.swift
//  FinanceTracker
//
//  Created by Enzo on 10/12/25.
//

import SwiftUI
import SwiftData
import SageKit

struct TagCapsule: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tag: ExpenseTag?
    let size: TagCapsuleSize
    var aiSuggested: Bool = false
    /// Drives the selected/unselected treatment in pickers. Display-only uses leave this at
    /// `true` so the capsule reads at full strength.
    var isSelected: Bool = true

    enum TagCapsuleSize {
        case xsmall
        case small
        case medium
    }

    init(tag: ExpenseTag?, _ size: TagCapsuleSize = .small, aiSuggested: Bool = false, isSelected: Bool = true) {
        self.tag = tag
        self.size = size
        self.aiSuggested = aiSuggested
        self.isSelected = isSelected
    }

    var verticalPadding: CGFloat {
        switch size {
        case .xsmall: 2
        case .small: 4
        case .medium: 6
        }
    }
    
    var horizontalPadding: CGFloat {
        switch size {
        case .xsmall: 6
        case .small: 8
        case .medium: 12
        }
    }
    
    var font: Font {
        switch size {
        case .xsmall: .caption
        case .small: .footnote
        case .medium: .subheadline
        }
    }

    /// Border thickness scales with capsule size.
    var borderWidth: CGFloat {
        switch size {
        case .xsmall: 1.5
        case .small: 2
        case .medium: 2.5
        }
    }

    @State private var gradientRotation: Double = 0
    /// Drives the AI glow's fade in → hold → fade out. The capsule's own border stays put
    /// underneath, so the glow can come and go without leaving the chip unbordered.
    @State private var glowOpacity: Double = 0
    @State private var glowTask: Task<Void, Never>? = nil

    private static let rainbow: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .red]

    var body: some View {
        if let tag, !tag.isDeleted {
            Text(glyph: tag.glyph, name: tag.name)
                .foregroundStyle(.primary)
                .font(font)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(Capsule().fill(isSelected ? AnyShapeStyle(tag.color.quaternary) : AnyShapeStyle(.cardBackground)))
                .accessibilityLabel("Tag: \(tag.name)")
                .overlay {
                    if isSelected {
                        Capsule().strokeBorder(tag.color, lineWidth: borderWidth)
                    } else {
                        Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: borderWidth)
                    }
                }
                .overlay { rainbowGlow }
                .onAppear {
                    if aiSuggested, !reduceMotion { playGlow() }
                }
                .onChange(of: aiSuggested) { _, newValue in
                    if newValue, !reduceMotion {
                        playGlow()
                    } else {
                        glowTask?.cancel()
                        withAnimation(.easeOut(duration: 0.3)) { glowOpacity = 0 }
                    }
                }
                .onChange(of: reduceMotion) { _, shouldReduceMotion in
                    if shouldReduceMotion {
                        glowTask?.cancel()
                        glowOpacity = 0
                    } else if aiSuggested {
                        playGlow()
                    }
                }
        }
    }

    // MARK: - Rainbow Glow
    
    private var rainbowGlow: some View {
        let gradient = AngularGradient(
            colors: Self.rainbow,
            center: .center,
            angle: .degrees(gradientRotation)
        )
        return ZStack {
            Capsule().stroke(gradient, lineWidth: borderWidth * 2.5).blur(radius: 7)
            Capsule().stroke(gradient, lineWidth: borderWidth * 1.4).blur(radius: 2.5)
            Capsule().strokeBorder(gradient, lineWidth: borderWidth * 0.8)
        }
        .opacity(glowOpacity * Self.glowPeakOpacity)
        .allowsHitTesting(false)
    }

    private static let glowPeakOpacity: Double = 0.5

    private func playGlow() {
        glowTask?.cancel()
        glowTask = Task { @MainActor in
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                gradientRotation = 360
            }
            withAnimation(.easeOut(duration: 0.45)) { glowOpacity = 1 }

            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.9)) { glowOpacity = 0 }

            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            // Replace the repeating spin so it isn't left running behind an invisible glow.
            withAnimation(.linear(duration: 0)) { gradientRotation = 0 }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        TagCapsule(tag: ExpenseTag.dining, .xsmall)
        TagCapsule(tag: ExpenseTag.dining, .small)
        TagCapsule(tag: ExpenseTag.dining, .medium)
        TagCapsule(tag: ExpenseTag.dining, .medium, aiSuggested: true)
        TagCapsule(tag: ExpenseTag.dining, .medium, isSelected: false)
    }
}
