import SwiftUI
import SageKit

struct OnboardingBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let base = Color.sageBackground
        let warmth = Color(red: 1, green: 0.78, blue: 0.58)
        let sunlight = Color(red: 1, green: 0.91, blue: 0.62)
        let intensity = colorScheme == .dark ? 0.3 : 1.0

        if reduceTransparency {
            base
        } else {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5, 0.5], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: [
                    base, base.mix(with: sunlight, by: 0.3 * intensity), base.mix(with: .sage, by: 0.3 * intensity),
                    base.mix(with: warmth, by: 0.6 * intensity), base.mix(with: sunlight, by: 0.35 * intensity), base,
                    base.mix(with: .sage, by: 0.25 * intensity), base, base.mix(with: .sage, by: 0.4 * intensity)
                ]
            )
        }
    }
}
