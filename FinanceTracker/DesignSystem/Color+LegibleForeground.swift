import SwiftUI

extension Color {
    /// Chooses the higher-contrast foreground for an opaque badge fill.
    func legibleForeground(in environment: EnvironmentValues) -> Color {
        let resolved = resolve(in: environment)
        let luminance = 0.2126 * resolved.linearRed
            + 0.7152 * resolved.linearGreen
            + 0.0722 * resolved.linearBlue
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return blackContrast >= whiteContrast ? .black : .white
    }
}
