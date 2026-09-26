//
//  SettingsViewNew.swift
//  FinanceTracker
//
//  Created by Enzo on 5/18/26.
//
import SwiftUI
import SwiftData
import WebKit
import WidgetKit
import Darwin
import SageKit

struct SettingsView: View {
    @Environment(AppConfiguration.self) private var config: AppConfiguration
    @Environment(AppRouter.self) private var router: AppRouter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.recurringReminders) private var reminders

    @State private var showExpenseDeletionOptions = false
    @State private var showFullResetConfirmation = false
    @State private var activeDataOperation: DataOperation?

    private var isChangingData: Bool { activeDataOperation != nil }

    private var feedbackURL: URL? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let ios = UIDevice.current.systemVersion
        let body = "\n\n\n--- Please do not remove the info below ---\nSyl \(version) (\(build)) · iOS \(ios) · \(Self.deviceModel)"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "contact@getsyl.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Syl Feedback"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    private static var deviceModel: String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
        #endif
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.settingsPath) {
            List {
                Section {
                    let page = SettingsPage.appearance
                    NavigationLink(value: page) {
                        SettingsListItem(text: page.rawValue, icon: page.icon, color: page.color)
                    }
                }

                Section {
                    ForEach([SettingsPage.budget, .recurringExpenses, .notifications, .tags], id: \.self) { page in
                        NavigationLink(value: page) {
                            SettingsListItem(text: page.rawValue, icon: page.icon, color: page.color)
                        }
                    }
                }

                Section {
                    let page = SettingsPage.backup
                    NavigationLink(value: page) {
                        SettingsListItem(text: page.rawValue, icon: page.icon, color: page.color)
                    }
                }

                Section {
                    if let feedbackURL {
                        Link(destination: feedbackURL) {
                            SettingsListItem(text: "Feedback", icon: "envelope.fill", color: .yellow)
                        }
                        .tint(.primary)
                    } else {
                        SettingsListItem(text: "Feedback unavailable", icon: "envelope.fill", color: .gray)
                    }
                    let page = SettingsPage.privacy
                    NavigationLink(value: page) {
                        SettingsListItem(text: page.rawValue, icon: page.icon, color: page.color)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showExpenseDeletionOptions = true
                    } label: {
                        SettingsListItem(text: "Delete Expense Data", icon: "trash.fill", color: .red)
                            .foregroundStyle(.red)
                    }
                    .disabled(isChangingData)

                    Button(role: .destructive) {
                        showFullResetConfirmation = true
                    } label: {
                        SettingsListItem(text: "Delete All Data", icon: "trash.circle.fill", color: .red)
                            .foregroundStyle(.red)
                    }
                    .disabled(isChangingData)
                } footer: {
                    Text("Delete All Data also removes settings and Syl's local CSV export. Copies saved or shared outside Syl are not deleted.")
                }

                #if DEBUG
                Section("Debug") {
                    Button(role: .destructive) {
                        config.resetRemoteSetup()
                        UserDefaults.standard.removeObject(forKey: "hasOpenedAppOnce")
                    } label: {
                        SettingsListItem(text: "Reset Onboarding", icon: "arrow.counterclockwise", color: .orange)
                            .foregroundStyle(.orange)
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .settingsBackground()
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .appearance:
                    AppearanceSettingsSection()
                case .budget:
                    BudgetSettingsSection()
                case .recurringExpenses:
                    RecurringExpensesSettingsSection()
                case .notifications:
                    NotificationsSettingsSection()
                case .tags:
                    TagsSettingsSection()
                case .backup:
                    ExpenseBackupSettingsSection()
                case .privacy:
                    PrivacyWebView()
                }
            }
            .alert("Choose What to Delete", isPresented: $showExpenseDeletionOptions) {
                Button("Delete Expenses Only", role: .destructive) {
                    Task { await performDataOperation(.expensesOnly) }
                }
                .disabled(isChangingData)
                Button("Delete Expenses and Recurring Rules", role: .destructive) {
                    Task { await performDataOperation(.expensesAndRecurringRules) }
                }
                .disabled(isChangingData)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Delete Expenses Only removes every expense, but recurring rules stay active and can create expenses again. Delete Expenses and Recurring Rules prevents those expenses from returning. Both actions are permanent.")
            }
            .alert("Delete All Data?", isPresented: $showFullResetConfirmation) {
                Button("Delete All Data", role: .destructive) {
                    Task { await performDataOperation(.fullReset) }
                }
                .disabled(isChangingData)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes all expenses, recurring rules, tags, accounts, settings, and Syl's local CSV export. Copies saved to Files or shared outside Syl cannot be recalled and must be deleted separately. This cannot be undone.")
            }
            .safeAreaInset(edge: .bottom) {
                if let activeDataOperation {
                    ProgressView(activeDataOperation.progressMessage)
                        .font(.subheadline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                        .accessibilityLabel("\(activeDataOperation.progressMessage). In progress.")
                }
            }
        }
    }

    private func performDataOperation(_ operation: DataOperation) async {
        guard activeDataOperation == nil else { return }
        activeDataOperation = operation
        router.showToast(SageToast(message: operation.progressMessage + "…", kind: .progress))
        defer { activeDataOperation = nil }

        await Task.yield()

        let deletionService = DataDeletionService(modelContext: modelContext)
        do {
            switch operation {
            case .expensesOnly:
                try deletionService.deleteExpenses(includeRecurringRules: false)
            case .expensesAndRecurringRules:
                try deletionService.deleteExpenses(includeRecurringRules: true)
                reminders?.refresh()
            case .fullReset:
                try deletionService.deleteAllUserData()
                config.resetAllSettings()
                reminders?.refresh()
            }

            WidgetCenter.shared.reloadAllTimelines()
            router.showToast(SageToast(message: operation.successMessage, kind: .success))
        } catch {
            // Only pending model changes can be rolled back, not an already-removed CSV.
            deletionService.rollback()
            router.showToast(
                SageToast(message: operation.failureMessage, kind: .error)
            )
        }
    }
}

private enum DataOperation {
    case expensesOnly
    case expensesAndRecurringRules
    case fullReset

    var progressMessage: String {
        switch self {
        case .expensesOnly: "Deleting expenses"
        case .expensesAndRecurringRules: "Deleting expenses and recurring rules"
        case .fullReset: "Deleting all data"
        }
    }

    var successMessage: String {
        switch self {
        case .expensesOnly: "All expenses deleted. Recurring rules are still active."
        case .expensesAndRecurringRules: "All expenses and recurring rules deleted."
        case .fullReset: "Syl data, settings, and local export deleted. External copies are unchanged."
        }
    }

    var failureMessage: String {
        switch self {
        case .expensesOnly: "Syl could not delete the expenses. Check storage and try again."
        case .expensesAndRecurringRules: "Syl could not delete the expenses and recurring rules. Check storage and try again."
        case .fullReset: "Syl could not finish deleting all data. Some data may already be removed. Check storage and try again."
        }
    }
}

struct SettingsListItem: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .frame(width: 35, height: 35)
                    .foregroundStyle(color)
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(text)
                .fontWeight(.bold)
        }
    }
}

enum SettingsPage: String, Hashable, CaseIterable {
    case appearance = "Appearance"
    case budget = "Budget and Allocation"
    case recurringExpenses = "Recurring Expenses"
    case notifications = "Notifications"
    case tags = "Tags"
    case backup = "Backup"
    case privacy = "Privacy"

    var icon: String {
        switch self {
        case .appearance: "paintpalette.fill"
        case .budget: "chart.bar.horizontal.page.fill"
        case .recurringExpenses: "arrow.trianglehead.clockwise"
        case .notifications: "bell.fill"
        case .tags: "tag.fill"
        case .backup: "cloud.fill"
        case .privacy: "hand.raised.fill"
        }
    }

    var color: Color {
        switch self {
        case .appearance: .sage
        case .budget: .green
        case .tags: .purple
        case .recurringExpenses: .orange
        case .notifications: .sage
        case .backup: .blue
        case .privacy: .red
        }
    }
}

private struct PrivacyWebView: View {
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

#Preview {
    @Previewable @State var appConfig: AppConfiguration = .preview
    SettingsView()
        .environment(appConfig)
        .environment(AppRouter())
        .modelContainer(SageModelContainer.preview)
}
