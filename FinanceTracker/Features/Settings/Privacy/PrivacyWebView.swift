import SwiftUI
import WebKit

struct PrivacyWebView: View {
    @State private var isReaderMode = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var reloadID = UUID()
    private let privacyURL = URL(string: "https://getsyl.app/privacy")

    var body: some View {
        Group {
            if let privacyURL {
                ZStack {
                    WebView(
                        url: privacyURL,
                        isReaderMode: isReaderMode,
                        reloadID: reloadID,
                        isLoading: $isLoading,
                        loadError: $loadError
                    )
                    .ignoresSafeArea()

                    if isLoading {
                        ProgressView("Loading privacy policy")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let loadError {
                        ContentUnavailableView {
                            Label("Privacy policy unavailable", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(loadError)
                        } actions: {
                            Button("Try Again") {
                                self.loadError = nil
                                isLoading = true
                                reloadID = UUID()
                            }
                            Link("Open in Browser", destination: privacyURL)
                        }
                        .background(.background)
                    }
                }
            } else {
                ContentUnavailableView("Privacy policy unavailable", systemImage: "exclamationmark.triangle")
            }
        }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isReaderMode.toggle()
                    } label: {
                        Image(systemName: isReaderMode ? "doc.plaintext.fill" : "doc.plaintext")
                    }
                    .accessibilityLabel(isReaderMode ? "Turn off reader mode" : "Turn on reader mode")
                    .accessibilityValue(isReaderMode ? "On" : "Off")
                }
            }
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    let isReaderMode: Bool
    let reloadID: UUID
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.plainLinkTapsJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.reloadID = reloadID
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.isReaderMode = isReaderMode
        context.coordinator.isLoading = $isLoading
        context.coordinator.loadError = $loadError

        if context.coordinator.reloadID != reloadID {
            context.coordinator.reloadID = reloadID
            webView.load(URLRequest(url: url))
        } else {
            Self.applyReaderMode(isReaderMode, to: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(policyURL: url, isLoading: $isLoading, loadError: $loadError, isReaderMode: isReaderMode)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let policyURL: URL
        var isLoading: Binding<Bool>
        var loadError: Binding<String?>
        var isReaderMode: Bool
        var reloadID: UUID?

        init(policyURL: URL, isLoading: Binding<Bool>, loadError: Binding<String?>, isReaderMode: Bool) {
            self.policyURL = policyURL
            self.isLoading = isLoading
            self.loadError = loadError
            self.isReaderMode = isReaderMode
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let frame: PrivacyPolicyNavigation.Frame = switch navigationAction.targetFrame?.isMainFrame {
            case nil: .newWindow
            case true?: .main
            case false?: .subframe
            }
            let decision = PrivacyPolicyNavigation.decision(
                for: url,
                in: frame,
                isLinkTap: navigationAction.navigationType == .linkActivated,
                policyURL: policyURL
            )
            switch decision {
            case .load:
                decisionHandler(.allow)
            case .openExternally:
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            loadError.wrappedValue = nil
            isLoading.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            isLoading.wrappedValue = false
            WebView.applyReaderMode(isReaderMode, to: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: Error
        ) {
            show(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: Error
        ) {
            show(error)
        }

        private func show(_ error: Error) {
            isLoading.wrappedValue = false
            loadError.wrappedValue = "Check your internet connection and try again."
        }
    }

    private static func applyReaderMode(_ isEnabled: Bool, to webView: WKWebView) {
        let js = isEnabled ? enableReaderModeJS : disableReaderModeJS
        webView.evaluateJavaScript(js)
    }

    private static let enableReaderModeJS = """
    (function() {
        var s = document.getElementById('sage-reader');
        if (!s) { s = document.createElement('style'); s.id = 'sage-reader'; document.head.appendChild(s); }
        s.textContent = `
            header, footer, nav, aside, .sidebar, .menu, .ad, [class*="cookie"], [class*="banner"] { display: none !important; }
            :root { color-scheme: light dark !important; }
            body { max-width: 660px !important; margin: 0 auto !important; padding: 24px 20px !important;
                   font-family: -apple-system, Georgia, serif !important; font-size: 17px !important;
                   line-height: 1.75 !important; color: CanvasText !important; background: Canvas !important; }
            img { max-width: 100% !important; }
        `;
    })();
    """

    private static let disableReaderModeJS = """
    (function() { var s = document.getElementById('sage-reader'); if (s) s.remove(); })();
    """

    /// getsyl.app's client-side router swaps in its own pages (Contact, home)
    /// without a real navigation, so the navigation delegate never sees them.
    /// Hiding link taps from the router makes every link a normal navigation.
    private static let plainLinkTapsJS = """
    window.addEventListener('click', function (event) {
        if (event.target instanceof Element && event.target.closest('a[href]')) {
            event.stopImmediatePropagation();
        }
    }, true);
    """
}
