import SwiftUI
import SageKit

struct ExpenseTagsPage: View {
    @Binding var tags: [ExpenseTag]
    @Binding var note: String
    var isNoteFocused: FocusState<Bool>.Binding
    var aiSuggestedTagIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Details")
                .font(.headline)
                .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 12) {
                Text("Tags (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                TagPicker(selectedTags: $tags, aiSuggestedTagIDs: aiSuggestedTagIDs) {
                    isNoteFocused.wrappedValue = false
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Note (optional)", systemImage: "text.alignleft")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Add a note", text: $note, axis: .vertical)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.sentences)
                    .lineLimit(3...5)
                    .focused(isNoteFocused)
                    .accessibilityLabel("Note")
                    .accessibilityHint("Optional")
                    .accessibilityIdentifier("expense-note-field")
            }
            .padding(16)
            .background(.cardBackground, in: .rect(cornerRadius: 16))
        }
        .sensoryFeedback(.selection, trigger: tags.map(\.id))
    }
}
