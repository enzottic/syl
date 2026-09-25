//
//  GradientBackgroundModifier.swift
//  FinanceTracker
//
//  Created by Enzo on 3/13/26.
//
import SwiftUI

struct GradientBackgroundModifier: ViewModifier {
    var color: Color
    
    init(_ color: Color) {
        self.color = color
    }
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            LinearGradient(
                colors: [color.opacity(0.3), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func gradientBackground(color: Color = .sage) -> some View {
        modifier(GradientBackgroundModifier(color))
    }

    /// Applies the Sage background treatment used by Settings lists.
    @ViewBuilder
    func settingsBackground() -> some View {
        if UIDevice.current.userInterfaceIdiom != .pad {
            scrollContentBackground(.hidden)
                .textCase(nil)
                .background(.sageBackground)
                .gradientBackground()
        } else {
            scrollContentBackground(.hidden)
                .textCase(nil)
                .background(.sageBackground)
        }
    }
}
