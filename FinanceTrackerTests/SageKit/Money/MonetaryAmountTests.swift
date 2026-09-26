import Foundation
import Testing
@testable import SageKit

struct MonetaryAmountTests {
    @Test(arguments: ["USD", "JPY", "KWD"])
    func acceptsWholeAmountsAndInclusiveLimit(currencyCode: String) {
        for amount in [1.0, 42, MonetaryAmount.maximumMagnitude] {
            #expect(MonetaryAmount.isValid(amount, currencyCode: currencyCode))
            #expect(MonetaryAmount.isValid(amount, currencyCode: currencyCode, requiresPositive: true))
        }
    }

    @Test(arguments: [
        ("USD", 0.01), ("USD", 12.34), ("USD", 999_999_999.99),
        ("JPY", 1.0), ("JPY", 1234.0),
        ("KWD", 0.001), ("KWD", 12.345), ("KWD", 48.695), ("KWD", 999_999_999.999)
    ])
    func acceptsMinorUnitsAndRefunds(currencyCode: String, amount: Double) {
        #expect(MonetaryAmount.isValid(amount, currencyCode: currencyCode))
        #expect(MonetaryAmount.isValid(-amount, currencyCode: currencyCode))
        #expect(!MonetaryAmount.isValid(-amount, currencyCode: currencyCode, requiresPositive: true))
    }

    @Test(arguments: [
        ("USD", 0.004), ("USD", 0.005), ("USD", 12.001), ("USD", 12.345), ("USD", 48.695),
        ("USD", 999_999_999.994),
        ("USD", 999_999_999.990001),
        ("JPY", 0.1), ("JPY", 12.5), ("JPY", 999_999_999.1),
        ("KWD", 0.0004), ("KWD", 12.3456), ("KWD", 999_999_999.9994),
        ("KWD", 999_999_999.999001)
    ])
    func rejectsExtraPrecisionWithoutRounding(currencyCode: String, amount: Double) {
        #expect(!MonetaryAmount.isValid(amount, currencyCode: currencyCode))
        #expect(!MonetaryAmount.isValid(-amount, currencyCode: currencyCode))
        #expect(!MonetaryAmount.isValid(amount, currencyCode: currencyCode, requiresPositive: true))
    }

    @Test(arguments: ["USD", "JPY", "KWD"])
    func rejectsNonfiniteZeroAndOversizedAmounts(currencyCode: String) {
        let invalid: [Double] = [
            .nan, .infinity, -.infinity, 0, -0.0,
            .leastNonzeroMagnitude, -.leastNonzeroMagnitude,
            .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
            MonetaryAmount.maximumMagnitude.nextUp,
            -MonetaryAmount.maximumMagnitude.nextUp,
            1_000_000_001, -1_000_000_001
        ]
        for amount in invalid {
            #expect(!MonetaryAmount.isValid(amount, currencyCode: currencyCode))
            #expect(!MonetaryAmount.isValid(amount, currencyCode: currencyCode, requiresPositive: true))
        }
        #expect(MonetaryAmount.isValid(-MonetaryAmount.maximumMagnitude, currencyCode: currencyCode))
    }

    @Test(arguments: [("USD", 12.34), ("JPY", 12.0), ("KWD", 12.345)])
    func toleratesOnlyBinaryRepresentationNoise(currencyCode: String, amount: Double) {
        #expect(MonetaryAmount.isValid(amount.nextUp, currencyCode: currencyCode))
        #expect(MonetaryAmount.isValid(amount.nextDown, currencyCode: currencyCode))
        #expect(MonetaryAmount.isValid(-amount.nextUp, currencyCode: currencyCode))
        #expect(!MonetaryAmount.isValid(amount + amount.ulp * 8, currencyCode: currencyCode))
        #expect(!MonetaryAmount.isValid(amount - amount.ulp * 8, currencyCode: currencyCode))
    }

    @Test
    func acceptsBinaryArithmetic() {
        let amount = 0.1 + 0.2
        #expect(MonetaryAmount.isValid(amount, currencyCode: "USD"))
        #expect(MonetaryAmount.isValid(-amount, currencyCode: "USD"))
        #expect(amount != 0.3)
    }

    @Test(arguments: [
        ("USD", 999_999_999.99), ("JPY", 999_999_999.0), ("KWD", 999_999_999.999)
    ])
    func largeAmountsOnlyTolerateAFewULPs(currencyCode: String, amount: Double) {
        #expect(MonetaryAmount.isValid(amount.nextUp, currencyCode: currencyCode))
        #expect(MonetaryAmount.isValid(amount.nextDown, currencyCode: currencyCode))
        #expect(!MonetaryAmount.isValid(amount + amount.ulp * 8, currencyCode: currencyCode))
        #expect(!MonetaryAmount.isValid(amount - amount.ulp * 8, currencyCode: currencyCode))
    }

    @Test(arguments: ["", "usd", "ZZZ", " USD "])
    func rejectsUnsupportedCurrency(currencyCode: String) {
        #expect(!MonetaryAmount.isValid(12, currencyCode: currencyCode))
    }
}
