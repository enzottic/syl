import Foundation

/// One denomination for all expenses, recurring rules, and budgets. Never converts amounts.
public enum LedgerCurrency {
    #if DEBUG
    public static let storageKey = "dev.ledgerCurrencyCode"
    #else
    public static let storageKey = "ledgerCurrencyCode"
    #endif

    public static let supportedCodes = Locale.commonISOCurrencyCodes.sorted()

    public enum Error: LocalizedError, Equatable {
        case invalidCode(String)
        case notEstablished
        case storageUnavailable

        public var errorDescription: String? {
            switch self {
            case .invalidCode(let code): "Choose a supported ISO currency code instead of '\(code)'."
            case .notEstablished: "Open Syl and confirm the currency for your expenses and budgets first."
            case .storageUnavailable: "Syl could not access the shared currency setting. Try opening the app again."
            }
        }
    }

    public static func validatedCode(_ code: String?) -> String? {
        guard let code, supportedCodes.contains(code) else { return nil }
        return code
    }

    public static func suggestedCode(locale: Locale = .current) -> String {
        validatedCode(locale.currency?.identifier) ?? "USD"
    }

    public static var currentCode: String? {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return "USD" }
        return persistedCode() ?? suggestedCode()
    }

    public static func persistedCode(
        defaults: UserDefaults? = SagePreferences.defaults
    ) -> String? {
        validatedCode(defaults?.string(forKey: storageKey))
    }

    public static func requireCode() throws -> String {
        guard let code = currentCode else { throw Error.notEstablished }
        return code
    }

    public static func setCode(
        _ code: String,
        defaults: UserDefaults? = SagePreferences.defaults
    ) throws {
        guard validatedCode(code) != nil else { throw Error.invalidCode(code) }
        guard let defaults else { throw Error.storageUnavailable }
        defaults.set(code, forKey: storageKey)
    }

    /// Remove the saved denomination so future reads use the locale suggestion.
    public static func reset(
        defaults: UserDefaults? = SagePreferences.defaults
    ) {
        defaults?.removeObject(forKey: storageKey)
        defaults?.removeObject(forKey: storageKey + ".conflict")
    }

    public static func fractionDigits(for code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }
}
