import Foundation
import SageKit

public nonisolated enum AmountInput {
    public static func parse(
        _ text: String,
        currencyCode: String,
        requiresPositive: Bool = false,
        locale: Locale = .current
    ) -> Double? {
        guard let amount = parse(text, locale: locale),
              MonetaryAmount.isValid(amount, currencyCode: currencyCode,
                                     requiresPositive: requiresPositive) else { return nil }
        return amount
    }

    public static func text(for amount: Double, locale: Locale = .current) -> String {
        amount.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...16)))
    }

    public static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        
        // Localized negative numbers may contain directional marks around the sign.
        let directionMarks = CharacterSet(charactersIn: "\u{061C}\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        
        func withoutDirectionMarks(_ value: String) -> String {
            String(String.UnicodeScalarView(value.unicodeScalars.filter { !directionMarks.contains($0) }))
        }
        
        var normalized = withoutDirectionMarks(text).trimmingCharacters(in: .whitespacesAndNewlines)
        let minus = withoutDirectionMarks(formatter.minusSign ?? "-")
        let plus = withoutDirectionMarks(formatter.plusSign ?? "+")
        var sign = ""
        
        if !minus.isEmpty, normalized.hasPrefix(minus) {
            sign = "-"
            normalized.removeFirst(minus.count)
        } else if normalized.hasPrefix("-") || normalized.hasPrefix("\u{2212}") {
            sign = "-"
            normalized.removeFirst()
        } else if !plus.isEmpty, normalized.hasPrefix(plus) {
            normalized.removeFirst(plus.count)
        } else if normalized.hasPrefix("+") {
            normalized.removeFirst()
        }
        
        let decimal = formatter.decimalSeparator ?? "."
        let grouping = formatter.groupingSeparator ?? ","
        let parts = normalized.components(separatedBy: decimal)
        
        guard parts.count <= 2 else { return nil }
        
        let groups = parts[0].components(separatedBy: grouping)
        if groups.count > 1 {
            let primary = formatter.groupingSize
            let secondary = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primary
            guard primary > 0, secondary > 0,
                  (1...secondary).contains(groups[0].count),
                  groups.last?.count == primary,
                  groups.dropFirst().dropLast().allSatisfy({ $0.count == secondary }) else { return nil }
        }
        
        // Only integer grouping is legal. Every other character must be a decimal digit.
        let integer = groups.joined()
        let fraction = parts.count == 2 ? parts[1] : ""
        var digits = sign
        for character in integer {
            if let value = character.wholeNumberValue, (0...9).contains(value) {
                digits.append(String(value))
            } else {
                return nil
            }
        }
        
        if parts.count == 2 {
            digits.append(".")
            for character in fraction {
                guard let value = character.wholeNumberValue, (0...9).contains(value) else { return nil }
                digits.append(String(value))
            }
        }
        
        guard let amount = Double(digits), amount.isFinite else { return nil }
        return amount
    }
}
