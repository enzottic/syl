import SwiftUI
import SwiftData
import SageKit

/// Shows which category/tag filters the Stats screen is scoped to, each removable in place.
/// Always occupies one chip row, so adding or removing a filter never shifts the content below.
struct StatsActiveFilters: View {
    @Environment(\.categoryColors) private var categoryColors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selectedCategory: ExpenseCategory?
    @Binding var selectedTag: ExpenseTag?

    /// A deleted tag no longer filters anything, so it isn't shown as active.
    private var activeTag: ExpenseTag? {
        guard let selectedTag, !selectedTag.isDeleted else { return nil }
        return selectedTag
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Reserves a chip's height at the current Dynamic Type size while no filter is shown.
            FilterChip(tint: .clear) {} label: { Text(verbatim: " ") }
                .hidden()
                .accessibilityHidden(true)

            // One row only: extra chips scroll sideways rather than wrapping and growing taller.
            ScrollView(.horizontal) {
                HStack(spacing: 8) { chips }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chips: some View {
        if let category = selectedCategory {
            FilterChip(tint: category.color(in: categoryColors)) {
                removeFilter { selectedCategory = nil }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(category.color(in: categoryColors))
                        .frame(width: 8, height: 8)
                    Text(category.rawValue)
                }
            }
            .accessibilityLabel("Filtered by category: \(category.rawValue)")
            .accessibilityHint("Remove category filter")
            .accessibilityIdentifier("stats-category-filter-chip")
        }

        if let tag = activeTag {
            FilterChip(tint: tag.color) {
                removeFilter { selectedTag = nil }
            } label: {
                Text(glyph: tag.glyph, name: tag.name)
            }
            .accessibilityLabel("Filtered by tag: \(tag.name)")
            .accessibilityHint("Remove tag filter")
            .accessibilityIdentifier("stats-tag-filter-chip")
        }
    }

    private func removeFilter(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35), change)
    }
}

private struct FilterChip<Content: View>: View {
    let tint: Color
    let action: () -> Void
    @ViewBuilder let label: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                label
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(0.15), in: .capsule)
            .overlay { Capsule().strokeBorder(tint, lineWidth: 1) }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var category: ExpenseCategory? = .wants
    @Previewable @State var tag: ExpenseTag? = .dining
    StatsActiveFilters(selectedCategory: $category, selectedTag: $tag)
        .padding()
        .environmentInjection()
}
