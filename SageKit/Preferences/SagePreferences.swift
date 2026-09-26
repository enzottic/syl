import Foundation

/// The app and its extensions use one preferences store per build environment.
public enum SagePreferences {
    #if DEBUG
    public static let suiteName = "group.me.enzottic.SageAppGroup.dev"
    #else
    public static let suiteName = "group.me.enzottic.SageAppGroup"
    #endif

    public static let defaults: UserDefaults = {
        let environment = ProcessInfo.processInfo.environment
        if environment["SAGE_UI_TESTING"] == "1" || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return UserDefaults(suiteName: "Sage.Isolated.\(UUID().uuidString)")!
        }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }()

}
