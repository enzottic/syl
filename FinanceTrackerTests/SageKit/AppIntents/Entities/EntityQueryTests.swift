import AppIntents
import CoreSpotlight
import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Expense and tag entities")
struct EntityQueryTests {
    @Test @MainActor
    func tagQueryMatchesNameInsensitivelyAndEmojiExactly() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let coffee = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
        let cafe = ExpenseTag(name: "Café Lunches", uiColor: .orange, emoji: "🥪")
        store.context.insert(coffee)
        store.context.insert(cafe)
        try store.save()
        var query = ExpenseTagEntityQuery()
        query.expenseStore = store

        #expect(try await query.entities(matching: " coff ").map(\.id) == [coffee.id])
        #expect(try await query.entities(matching: "cafe").map(\.id) == [cafe.id])
        #expect(try await query.entities(matching: "☕").map(\.id) == [coffee.id])
        #expect(try await query.entities(matching: "  ").isEmpty)
    }

    @Test @MainActor
    func tagQueryResolvesIdentifiers() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let coffee = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
        store.context.insert(coffee)
        store.context.insert(ExpenseTag(name: "Travel", uiColor: .blue, emoji: "✈️"))
        try store.save()
        var query = ExpenseTagEntityQuery()
        query.expenseStore = store

        #expect(try await query.entities(for: [coffee.id, UUID()]).map(\.id) == [coffee.id])
    }

    @Test @MainActor
    func expenseQueryMatchesNotesAndTagNamesNewestFirst() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let tag = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
        let older = Expense(name: "Latte", amount: 5, date: .now.addingTimeInterval(-86_400), tags: [tag])
        let newer = Expense(name: "Beans", amount: 18, date: .now, note: "Coffee for the office")
        store.context.insert(tag)
        store.context.insert(older)
        store.context.insert(newer)
        store.context.insert(Expense(name: "Rent", amount: 1_200))
        try store.save()
        var query = ExpenseEntity.ExpenseEntityQuery()
        query.expenseStore = store

        #expect(try await query.entities(matching: "coffee").map(\.id) == [newer.id, older.id])
        #expect(try await query.entities(matching: "").isEmpty)
    }

    @Test @MainActor
    func expenseEntityCarriesNoteRecurrenceAndSpotlightAttributes() throws {
        let tag = ExpenseTag(name: "Streaming", uiColor: .red, emoji: "📺")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let expense = Expense(
            name: "Netflix", amount: 15.49, category: .wants, date: date,
            tags: [tag], note: "Family plan", recurringExpenseId: UUID()
        )

        let entity = expense.entity

        #expect(entity.note == "Family plan")
        #expect(entity.isRecurring)
        let attributes = entity.attributeSet
        #expect(attributes.contentDescription?.contains("Family plan") == true)
        #expect(attributes.keywords == ["Streaming", "Wants"])
        #expect(attributes.contentCreationDate == date)
        #expect(Expense(name: "Coffee", amount: 4).entity.isRecurring == false)
    }

    @Test
    func entitiesRequireAuthentication() {
        #expect(ExpenseEntity.authenticationPolicy == .requiresAuthentication)
        #expect(ExpenseTagEntity.authenticationPolicy == .requiresAuthentication)
    }
}
