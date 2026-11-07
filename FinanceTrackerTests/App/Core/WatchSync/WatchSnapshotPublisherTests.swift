import Foundation
import SwiftData
import Testing
@testable import SageKit

@Suite("Watch snapshot publisher")
@MainActor
struct WatchSnapshotPublisherTests {
    private final class Outbox {
        var snapshots: [WatchSnapshot] = []
    }

    @Test
    func intentSaveInAnotherContextPublishesOnce() async throws {
        let container = try SageModelContainer.make(for: .test)
        let outbox = Outbox()
        let publisher = makePublisher(container: container, outbox: outbox)
        publisher.start()

        let store = ExpenseStore(modelContainer: container)
        _ = try store.addExpenseAndSave(Expense(name: "Coffee", amount: 4.5, category: .wants), tagIDs: [])
        _ = try store.addExpenseAndSave(Expense(name: "Lunch", amount: 12, category: .wants), tagIDs: [])
        try await waitUntil(keeping: publisher) { !outbox.snapshots.isEmpty }
        try await waitForDebounce(keeping: publisher)

        #expect(outbox.snapshots.count == 1)
        #expect(outbox.snapshots.first?.totalSpent == 16.5)
    }

    @Test
    func savesToOtherContainersAreIgnored() async throws {
        let outbox = Outbox()
        let publisher = makePublisher(container: try SageModelContainer.make(for: .test), outbox: outbox)
        publisher.start()

        let other = try SageModelContainer.make(for: .test)
        other.mainContext.insert(Expense(name: "Elsewhere", amount: 1))
        try other.mainContext.save()
        try await waitForDebounce(keeping: publisher)

        #expect(outbox.snapshots.isEmpty)
    }

    @Test
    func nothingIsSentBeforeOnboarding() async throws {
        let container = try SageModelContainer.make(for: .test)
        let outbox = Outbox()
        let publisher = makePublisher(container: container, outbox: outbox, isOnboarded: false)
        publisher.start()

        container.mainContext.insert(Expense(name: "Coffee", amount: 4.5))
        try container.mainContext.save()
        try await waitForDebounce(keeping: publisher)
        publisher.publish()

        #expect(outbox.snapshots.isEmpty)
    }

    private func makePublisher(container: ModelContainer, outbox: Outbox, isOnboarded: Bool = true) -> WatchSnapshotPublisher {
        WatchSnapshotPublisher(
            container: container,
            configuration: .preview,
            debounce: .milliseconds(20),
            isOnboarded: { isOnboarded },
            send: { outbox.snapshots.append($0) }
        )
    }

    // The observers hold the publisher weakly, so the waits keep it alive. Other main-actor tests
    // run in parallel, so publishing can lag well behind the debounce.
    private func waitUntil(keeping publisher: WatchSnapshotPublisher, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        withExtendedLifetime(publisher) {}
    }

    private func waitForDebounce(keeping publisher: WatchSnapshotPublisher) async throws {
        try await Task.sleep(for: .milliseconds(300))
        withExtendedLifetime(publisher) {}
    }
}
