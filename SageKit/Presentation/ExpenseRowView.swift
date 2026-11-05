//
//  ExpenseRowView.swift
//  SageKit
//

import SwiftUI

/// The expense row from Syl's lists, shared with Siri's result cards.
public struct ExpenseRowView: View {
    public enum Style: Codable, Sendable {
        case regular
        /// Single-line layout for tight spaces like dashboard cards.
        case condensed
    }

    @Environment(\.self) private var environment

    let name: String
    let amount: String
    let date: String
    let categoryColor: Color
    let glyph: TagGlyph?
    let extraTagCount: Int
    let isRecurring: Bool
    let style: Style

    public init(
        name: String,
        amount: String,
        date: String,
        categoryColor: Color,
        glyph: TagGlyph?,
        extraTagCount: Int = 0,
        isRecurring: Bool,
        style: Style = .regular
    ) {
        self.name = name
        self.amount = amount
        self.date = date
        self.categoryColor = categoryColor
        self.glyph = glyph
        self.extraTagCount = extraTagCount
        self.isRecurring = isRecurring
        self.style = style
    }

    public var body: some View {
        switch style {
        case .regular: regularContent
        case .condensed: condensedContent
        }
    }

    private var regularContent: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(categoryColor.secondary)
                    .frame(width: 40, height: 40)
                if let glyph {
                    TagGlyphView(glyph)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if extraTagCount > 0 {
                    Text("+\(extraTagCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(categoryColor.legibleForeground(in: environment))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(categoryColor))
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isRecurring {
                        recurringMark
                    }
                }
            }

            Spacer()

            Text(amount)
                .font(.body)
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }

    private var condensedContent: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(categoryColor.secondary)
                    .frame(width: 24, height: 24)
                if let glyph {
                    TagGlyphView(glyph)
                        .font(.caption)
                }
            }

            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .layoutPriority(-1)

            if isRecurring {
                recurringMark
            }

            Spacer()

            Text(date)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()

            Text(amount)
                .font(.subheadline)
                .fontWeight(.medium)
                .fixedSize()
        }
    }

    private var recurringMark: some View {
        Image(systemName: "arrow.trianglehead.2.clockwise")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
