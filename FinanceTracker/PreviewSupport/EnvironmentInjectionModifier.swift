//
//  EnvironmentInjectionModifier.swift
//  FinanceTracker
//
//  Created by Enzo on 5/19/26.
//
import SwiftUI
import SwiftData
import SageKit

extension View {
    func environmentInjection(empty: Bool = false, container: ModelContainer? = nil) -> some View {
        modifier(EnvironmentInjection(container: container ?? (empty ? SageModelContainer.previewEmpty : SageModelContainer.preview)))
    }
}

struct EnvironmentInjection: ViewModifier {
    @State var config = AppConfiguration.preview
    @State var appRouter = AppRouter()
    
    let container: ModelContainer
    
    func body(content: Content) -> some View {
        content
            .modelContainer(container)
            .environment(config)
            .environment(appRouter)
            .environment(\.categoryColors, config.categoryColors)
            .fontDesign(.rounded)
    }
}
