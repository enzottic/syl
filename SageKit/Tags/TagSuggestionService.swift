//
//  TagSuggestionService.swift
//  SageKit
//
//  Created by enzo ! on 5/16/26.
//

import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

public final class TagSuggestionService {
    public init() {}

    // MARK: - AI availability

    public static var isAIAvailable: Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    // MARK: - AI types

    #if canImport(FoundationModels)
    @Generable(description: "A tag suggestion for an expense")
    struct TagSuggestion {
        @Guide(description: "The name of the most appropriate tag from the provided list, exactly as written in the list")
        var tagName: String
    }
    #endif

    // MARK: - Public interface

    public func suggestTag(
        for expenseName: String,
        existingExpenses: [(name: String, tagName: String?)],
        tagNames: [String],
        smartTaggingMode: SmartTaggingMode
    ) async -> (tagName: String, source: SuggestionSource)? {
        let trimmed = expenseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tagNames.isEmpty else { return nil }

        // History — always available, runs for .history and .both
        if smartTaggingMode == .history || smartTaggingMode == .both {
            if let match = suggestTagFromHistory(trimmed, existingExpenses, tagNames) {
                return (match, .history)
            }
        }

        // AI — runs for .ai, and as fallback for .both when history missed
        #if canImport(FoundationModels)
        if smartTaggingMode == .ai || smartTaggingMode == .both {
            if let match = await suggestTagWithAI(trimmed, tagNames) {
                return (match, .ai)
            }
        }
        #endif

        return nil
    }

    // MARK: - History

    private func suggestTagFromHistory(
        _ expenseName: String,
        _ existingExpenses: [(name: String, tagName: String?)],
        _ tagNames: [String]
    ) -> String? {
        guard let historyTag = existingExpenses.first(where: {
            $0.name.lowercased() == expenseName.lowercased() && $0.tagName != nil
        })?.tagName else { return nil }

        return tagNames.first { $0.lowercased() == historyTag.lowercased() }
    }

    // MARK: - AI

    #if canImport(FoundationModels)
    private func suggestTagWithAI(
        _ expenseName: String,
        _ tagNames: [String]
    ) async -> String? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let tagList = tagNames.joined(separator: ", ")
        let instructions = Instructions("""
            You are a tag classifier for a personal expense tracker. \
            Given an expense name, pick the single most appropriate tag from the provided list. \
            You MUST respond with exactly one tag name from the list, spelled exactly as provided. \
            If none fit well, respond with "Other".
            """)

        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Expense: \"\(expenseName)\". Available tags: \(tagList)."

        do {
            let response = try await session.respond(to: prompt, generating: TagSuggestion.self)
            let suggested = response.content.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            return tagNames.first { $0.lowercased() == suggested.lowercased() }
        } catch {
            return nil
        }
    }
    #endif
}

extension TagSuggestionService {
    /// Shared by the add sheet and Siri. Hidden tags are never suggested.
    @MainActor
    public func suggestTag(
        forExpenseNamed name: String,
        tags: [ExpenseTag],
        in context: ModelContext,
        mode: SmartTaggingMode
    ) async -> (tag: ExpenseTag, source: SuggestionSource)? {
        let eligible = tags.filter { !$0.isHiddenFromExpenseEntry }
        let history = (try? ExpenseSuggestionHistory.newestTaggedMatch(for: name, in: context)).map { [$0] } ?? []
        guard let suggestion = await suggestTag(
                for: name, existingExpenses: history, tagNames: eligible.map(\.name), smartTaggingMode: mode),
              let tag = eligible.first(where: { $0.name == suggestion.tagName }) else { return nil }
        return (tag, suggestion.source)
    }
}

public enum SuggestionSource: Sendable {
    case history
    case ai
}
