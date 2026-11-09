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
    let categoryName: String?
    let categoryColor: Color
    let glyph: TagGlyph?
    let tagColor: Color?
    let extraTagCount: Int
    let isRecurring: Bool
    let style: Style

    public init(
        name: String,
        amount: String,
        date: String,
        categoryName: String? = nil,
        categoryColor: Color,
        glyph: TagGlyph?,
        tagColor: Color? = nil,
        extraTagCount: Int = 0,
        isRecurring: Bool,
        style: Style = .regular
    ) {
        self.name = name
        self.amount = amount
        self.date = date
        self.categoryName = categoryName
        self.categoryColor = categoryColor
        self.glyph = glyph
        self.tagColor = tagColor
        self.extraTagCount = extraTagCount
        self.isRecurring = isRecurring
        self.style = style
    }

    private var badgeColor: Color { tagColor ?? categoryColor }

    private var badgeFill: Color { badgeColor.opacity(0.18) }

    private var dateLine: String {
        categoryName.map { "\($0) · \(date)" } ?? date
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
                    .fill(badgeFill)
                    .frame(width: 40, height: 40)
                if let glyph {
                    TagGlyphView(glyph)
                        .foregroundStyle(badgeColor)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if extraTagCount > 0 {
                    Text("+\(extraTagCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(badgeColor.legibleForeground(in: environment))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(badgeColor))
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(dateLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

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
                    .fill(badgeFill)
                    .frame(width: 24, height: 24)
                if let glyph {
                    TagGlyphView(glyph)
                        .font(.caption)
                        .foregroundStyle(badgeColor)
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
