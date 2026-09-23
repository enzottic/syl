import SwiftUI

struct ExpenseNamePage<HeaderAction: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var name: String
    var nameFocus: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    @ViewBuilder var headerAction: HeaderAction

    @State private var placeholderIndex = 0
    private let placeholders = ["Gas", "Groceries", "Streaming service", "Coffee", "Dinner"]

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                Text("What did you buy?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                headerAction
                    .frame(width: 44, height: 44)
            }

            TextField("Expense name", text: $name, prompt: Text(""))
                .focused(nameFocus)
                .textFieldStyle(.plain)
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .onSubmit(onSubmit)
                .accessibilityLabel("Expense name")
                .overlay {
                    if name.isEmpty {
                        Text(placeholders[placeholderIndex])
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .id(placeholderIndex)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 12)
        }
        .task {
            nameFocus.wrappedValue = true
        }
        .task(id: name.isEmpty) {
            guard name.isEmpty else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    placeholderIndex = (placeholderIndex + 1) % placeholders.count
                }
            }
        }
    }
}
