import Foundation
import Testing

@Suite("Privacy policy link routing")
struct PrivacyPolicyNavigationTests {
    private let policyURL = URL(string: "https://getsyl.app/privacy")!

    private func decision(
        _ string: String,
        in frame: PrivacyPolicyNavigation.Frame = .main,
        isLinkTap: Bool = true
    ) -> PrivacyPolicyNavigation.Decision {
        PrivacyPolicyNavigation.decision(for: URL(string: string)!, in: frame, isLinkTap: isLinkTap, policyURL: policyURL)
    }

    @Test
    func loadsThePolicyItself() {
        #expect(decision("https://getsyl.app/privacy", isLinkTap: false) == .load)
        #expect(decision("https://getsyl.app/privacy/", isLinkTap: false) == .load)
    }

    @Test
    func tappingThePolicyOrOneOfItsSectionsStaysInPlace() {
        #expect(decision("https://getsyl.app/privacy") == .load)
        #expect(decision("https://getsyl.app/privacy/") == .load)
        #expect(decision("https://getsyl.app/privacy#contact") == .load)
    }

    @Test(arguments: [
        "mailto:contact@getsyl.app",
        "https://www.apple.com/legal/privacy/",
        "https://developers.cloudflare.com/web-analytics/faq/",
        "https://www.adobe.com/privacy/policy.html",
        "https://enzottic.me",
        "https://getsyl.app/",
        "https://getsyl.app/contact",
    ])
    func tappedLinksOpenOutsideTheApp(_ link: String) {
        #expect(decision(link) == .openExternally)
    }

    @Test
    func nonWebSchemesNeverLoadInTheMainFrame() {
        #expect(decision("mailto:contact@getsyl.app", isLinkTap: false) == .openExternally)
        #expect(decision("tel:5555555555", isLinkTap: false) == .openExternally)
    }

    @Test
    func redirectsAndScriptNavigationsStayInTheWebView() {
        #expect(decision("https://www.getsyl.app/privacy", isLinkTap: false) == .load)
    }

    @Test
    func newWindowLinksOpenOutsideTheApp() {
        #expect(decision("https://getsyl.app/privacy", in: .newWindow) == .openExternally)
        #expect(decision("https://www.apple.com", in: .newWindow, isLinkTap: false) == .openExternally)
    }

    @Test
    func subframesLoadNormally() {
        #expect(decision("https://www.apple.com", in: .subframe) == .load)
        #expect(decision("about:blank", in: .subframe, isLinkTap: false) == .load)
    }
}
