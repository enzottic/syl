import SwiftUI
import SageKit

struct ExpenseTagsPage: View {
    @Binding var tags: [ExpenseTag]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.headline)
                .padding(.horizontal, 10)
            TagPicker(selectedTags: $tags)
        }
        .sensoryFeedback(.selection, trigger: tags.map(\.id))
    }
}
