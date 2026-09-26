//
//  TagGlyphPickerSheet.swift
//  FinanceTracker
//

import SwiftUI
import SageKit

/// Lets the user pick a tag's mark as either an SF Symbol or an emoji.
struct TagGlyphPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var glyph: TagGlyph
    /// Tints the grids so the mark is previewed in the tag's own color.
    let tint: Color

    /// Case order drives the segmented control, so `icon` leads.
    private enum Mode: String, CaseIterable, Identifiable {
        case icon = "Icon"
        case emoji = "Emoji"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .icon
    @State private var search: String = ""
    @State private var emojiFieldFocused: Bool = false

    /// Picking is immediate — there's no pending selection to hold, so the chosen mark is written
    /// straight through to the binding and the sheet closes.
    private func pick(_ picked: TagGlyph) {
        glyph = picked
        dismiss()
    }

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Style", selection: $mode.animation(.easeInOut(duration: 0.2))) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch mode {
                case .icon: iconGrid
                case .emoji: emojiGrid
                }
            }
            .padding(.top)
            .searchable(text: $search, prompt: mode == .icon ? "Search icons" : "Search emoji")
            .navigationTitle("Tag Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            mode = glyph.symbolValue != nil ? .icon : .emoji
        }
    }

    // MARK: - Symbols

    private var iconGrid: some View {
        let sections = TagSymbolCatalog.sections(matching: search)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(section.entries) { entry in
                                symbolCell(entry.symbol)
                            }
                        }
                    } header: {
                        sectionHeader(section.title)
                    }
                }
            }
            .padding(.horizontal)
        }
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    private func symbolCell(_ symbol: String) -> some View {
        let isSelected = glyph.symbolValue == symbol
        return Button {
            pick(.symbol(symbol))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? .white : tint)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(tint.quaternary))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TagSymbolCatalog.accessibilityName(for: symbol))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Emoji

    private var emojiGrid: some View {
        let sections = TagEmojiCatalog.sections(matching: search)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(section.entries) { entry in
                                emojiCell(entry.emoji)
                            }
                        }
                    } header: {
                        sectionHeader(section.title)
                    }
                }

                keyboardEscapeHatch
            }
            .padding(.horizontal)
        }
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    private func emojiCell(_ value: String) -> some View {
        let isSelected = glyph.emojiValue == value
        return Button {
            pick(.emoji(value))
        } label: {
            Text(value)
                .font(.system(size: 26))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 12).fill(tint.quaternary))
                // Emoji ignore tinting, so selection reads as a border rather than a fill.
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(tint, lineWidth: isSelected ? 2.5 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The curated list can't cover every emoji, so the system keyboard stays reachable.
    private var keyboardEscapeHatch: some View {
        Button {
            emojiFieldFocused = true
        } label: {
            Label("Any emoji…", systemImage: "keyboard")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(tint.quaternary))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.top, 8)
        // Hosts the emoji keyboard; the button above is the visible tap target. The field reports
        // exactly one emoji, so writing to this binding is the pick.
        .background(
            EmojiKeyboardField(
                emoji: Binding(
                    get: { glyph.emojiValue ?? "" },
                    set: { pick(.emoji($0)) }
                ),
                isFocused: $emojiFieldFocused
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
        )
    }

    // MARK: - Shared

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .background(.background)
    }
}

#Preview {
    @Previewable @State var glyph: TagGlyph = .emoji("💰")
    TagGlyphPickerSheet(glyph: $glyph, tint: .blue)
}
