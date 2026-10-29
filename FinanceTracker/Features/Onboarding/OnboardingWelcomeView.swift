import SwiftUI
import SageKit

struct OnboardingWelcomeView: View {
    let onGetStarted: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 44) {
                    Image("LaunchIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(geometry.size.width * 0.46, 190))
                        .accessibilityHidden(true)

                    Text("welcome to syl")
                        .font(.custom("MomoTrustDisplay-Regular", size: 38, relativeTo: .largeTitle))
                        .fontDesign(nil)
                        .foregroundStyle(colorScheme == .dark ? Color.sage : .onSage)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)
                        .accessibilityIdentifier("onboarding-welcome-title")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onGetStarted) {
                HStack(spacing: 16) {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                }
                .font(.headline)
                .foregroundStyle(colorScheme == .dark ? Color.onSage : .sageBackground)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(colorScheme == .dark ? Color.sage : .onSage, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding-get-started-button")
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .task { headingFocused = true }
    }
}

#Preview("Sage Dawn") {
    OnboardingWelcomeView(onGetStarted: {})
        .background { OnboardingBackground().ignoresSafeArea() }
}

#Preview("Sage Dawn — Large Text") {
    OnboardingWelcomeView(onGetStarted: {})
        .environment(\.dynamicTypeSize, .accessibility3)
        .background { OnboardingBackground().ignoresSafeArea() }
}

#Preview("Sage Dawn — Dark") {
    OnboardingWelcomeView(onGetStarted: {})
        .background { OnboardingBackground().ignoresSafeArea() }
        .preferredColorScheme(.dark)
}
