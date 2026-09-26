//
//  TagGlyph.swift
//  FinanceTracker
//
//  The visual mark shown for a tag: either an emoji or an SF Symbol.
//

import SwiftUI

/// What a tag draws next to its name. Resolved from `ExpenseTag` rather than stored, so the
/// emoji/symbol precedence lives in exactly one place.
public enum TagGlyph: Hashable {
    case emoji(String)
    case symbol(String)

    /// The emoji, when this glyph is one. Lets callers outside SageKit branch without an
    /// exhaustive switch, which Swift 6 rejects for a non-frozen enum across module boundaries.
    public var emojiValue: String? {
        if case .emoji(let value) = self { return value }
        return nil
    }

    /// The SF Symbol name, when this glyph is one.
    public var symbolValue: String? {
        if case .symbol(let value) = self { return value }
        return nil
    }
}

public extension ExpenseTag {
    /// The tag's mark. Falls back to the emoji when `symbolName` is unset, and also when the
    /// stored name doesn't resolve on this OS — a tag written by a newer build shows its emoji
    /// rather than an empty box.
    var glyph: TagGlyph {
        if let symbolName, UIImage(systemName: symbolName) != nil {
            return .symbol(symbolName)
        }
        return .emoji(emoji)
    }
}

/// Draws a `TagGlyph` at the call site's font size, for the places that render the mark on its
/// own inside a shaped container. Sites that render the mark inline with the tag name should use
/// `Text(glyph:name:)` instead so the two share a baseline.
public struct TagGlyphView: View {
    private let glyph: TagGlyph

    public init(_ glyph: TagGlyph) {
        self.glyph = glyph
    }

    public init(tag: ExpenseTag) {
        self.glyph = tag.glyph
    }

    public var body: some View {
        switch glyph {
        case .emoji(let emoji):
            Text(emoji)
        case .symbol(let name):
            Image(systemName: name)
        }
    }
}

/// A tag's mark and name for use inside a `Menu` or menu-style `Picker`.
///
/// Those rows are rendered by UIKit, which drops an `Image` interpolated into a `Text` — the only
/// icon that survives is `Label`'s. Emoji are plain characters, so they stay as text.
public struct TagMenuLabel: View {
    /// Not named `tag`: that would shadow SwiftUI's `View.tag(_:)` modifier inside `body`.
    private let expenseTag: ExpenseTag

    public init(tag: ExpenseTag) {
        self.expenseTag = tag
    }

    public var body: some View {
        switch expenseTag.glyph {
        case .emoji(let emoji):
            Text("\(emoji) \(expenseTag.name)")
        case .symbol(let symbolName):
            Label(expenseTag.name, systemImage: symbolName)
        }
    }
}

public extension Text {
    /// A tag's mark followed by its name, as a single `Text`. Symbols are interpolated as images
    /// so they inherit the surrounding font and foreground style and sit on the text baseline,
    /// which keeps the emoji and symbol cases visually interchangeable.
    init(glyph: TagGlyph, name: String) {
        switch glyph {
        case .emoji(let emoji):
            self.init("\(emoji) \(name)")
        case .symbol(let symbolName):
            self.init("\(Image(systemName: symbolName)) \(name)")
        }
    }
}
