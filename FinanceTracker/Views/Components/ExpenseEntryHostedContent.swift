import SwiftUI

@Observable
final class ExpenseEntryContentState {
    var content = AnyView(EmptyView())
    var step = -1
    var animates = false
    var revision = 0
}

/// Keep the hosting controller's root fixed. Observable content updates then
/// participate in SwiftUI's own update graph, including replacement transitions.
struct ExpenseEntryHostedContent: View {
    let state: ExpenseEntryContentState
    @State private var displayedContent = AnyView(EmptyView())
    @State private var displayedStep = -1

    var body: some View {
        ZStack(alignment: .top) {
            displayedContent
                .id(displayedStep)
                .transition(.blurReplace)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: state.revision, initial: true) {
            let animation: Animation? = state.animates && displayedStep != state.step ? .smooth(duration: 0.3) : nil
            withAnimation(animation) {
                displayedContent = state.content
                displayedStep = state.step
            }
        }
    }
}
