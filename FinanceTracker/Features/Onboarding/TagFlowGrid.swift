import SwiftUI
import SageKit

struct TagFlowGrid: View {
    let tags: [ExpenseTag]
    @Binding var selectedTagNames: Set<String>

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(stride(from: 0, to: tags.count, by: 2)), id: \.self) { index in
                HStack(spacing: 12) {
                    tagButton(tags[index])
                    if index + 1 < tags.count {
                        tagButton(tags[index + 1])
                    }
                }
            }
        }
    }

    private func tagButton(_ tag: ExpenseTag) -> some View {
        let isSelected = selectedTagNames.contains(tag.name)
        return Button {
            if isSelected {
                selectedTagNames.remove(tag.name)
            } else {
                selectedTagNames.insert(tag.name)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tag.symbolName ?? "tag")
                    .accessibilityHidden(true)
                Text(tag.name)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isSelected ? Color.sage.opacity(0.2) : Color.cardBackground, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.sage : Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-tag-\(tag.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
