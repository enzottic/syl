//
//  PrivacyPolicyNavigation.swift
//  FinanceTracker
//

import Foundation

/// Decides where a navigation inside the in-app privacy policy goes.
///
/// The web view only ever shows the policy page. Every other link the user
/// taps (email addresses, Apple, Cloudflare, the rest of getsyl.app) opens in
/// the app that handles it, so the policy stays on screen behind it.
enum PrivacyPolicyNavigation {
    enum Decision: Equatable {
        case load
        case openExternally
    }

    enum Frame {
        case main
        case subframe
        /// A `target="_blank"` link or `window.open`. WKWebView has no
        /// window to put these in, so they would otherwise do nothing.
        case newWindow
    }

    static func decision(for url: URL, in frame: Frame, isLinkTap: Bool, policyURL: URL) -> Decision {
        switch frame {
        case .subframe:
            return .load
        case .newWindow:
            return .openExternally
        case .main:
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                // mailto:, tel:, … — WKWebView can't load these and silently drops them.
                return .openExternally
            }
            // Initial load, reload and redirects stay in the web view.
            guard isLinkTap else { return .load }
            return isPolicyPage(url, policyURL: policyURL) ? .load : .openExternally
        }
    }

    private static func isPolicyPage(_ url: URL, policyURL: URL) -> Bool {
        url.host()?.lowercased() == policyURL.host()?.lowercased()
            && trimmedPath(of: url) == trimmedPath(of: policyURL)
    }

    /// `/privacy` and `/privacy/` are the same page.
    private static func trimmedPath(of url: URL) -> String {
        var path = url.path()
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
