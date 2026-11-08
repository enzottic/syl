import AppIntents
import SwiftData

/// Every process that includes `SageKitPackage` can be chosen to run Syl's intents.
/// With the app closed, the system often picks the widget extension, so both must register.
@MainActor
public enum AppIntentDependencies {
    public static func register() {
        register(container: SageModelContainer.shared)
    }

    public static func register(container: Result<ModelContainer, any Error>) {
        let store: ExpenseStore
        switch container {
        case let .success(container):
            store = ExpenseStore(modelContainer: container)
        case .failure:
            guard let unavailableStore = try? ExpenseStore.unavailable() else { return }
            store = unavailableStore
        }
        AppDependencyManager.shared.add(dependency: store)
    }
}
