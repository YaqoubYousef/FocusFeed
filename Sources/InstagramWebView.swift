import SwiftUI
import WebKit

/// Full-screen Instagram website with Reels scrolling and "open in app" prompts removed.
struct InstagramWebView: UIViewRepresentable {
    let startURL: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()                 // keeps you logged in
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Look like mobile Safari so Instagram serves its normal mobile site.
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"

        let script = WKUserScript(source: FilterScript.source,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: true)
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true   // swipe from the edge to go back
        webView.allowsLinkPreview = false                    // no long-press previews popping up
        webView.isOpaque = true                              // opaque views draw faster
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.underPageBackgroundColor = .systemBackground

        context.coordinator.webView = webView
        context.coordinator.watchPageChanges(of: webView)   // pull-to-refresh where it makes sense

        // Block Instagram/Facebook tracking & logging requests before the first load.
        let startURL = self.startURL
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "FocusFeedBlocklist",
            encodedContentRuleList: Blocklist.rules
        ) { ruleList, _ in
            DispatchQueue.main.async {
                if let ruleList = ruleList {
                    webView.configuration.userContentController.add(ruleList)
                }
                // Opened by tapping a notification? Go straight to that conversation.
                let url = DeepLink.pending ?? startURL
                DeepLink.pending = nil
                webView.load(URLRequest(url: url))
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?

        override init() {
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(openPendingLink),
                                                   name: DeepLink.didRequestOpen, object: nil)
        }

        @objc private func openPendingLink() {
            DispatchQueue.main.async {
                guard let webView = self.webView, let url = DeepLink.pending else { return }
                DeepLink.pending = nil
                webView.load(URLRequest(url: url))
            }
        }

        // After each page load: copy the login cookies and user agent for the background inbox check.
        // MARK: Pull to refresh

        private var urlObservation: NSKeyValueObservation?

        /// Pull-to-refresh is on for the feed and profiles, off in DMs and reels
        /// (pulling down there should scroll messages, not reload the page).
        func watchPageChanges(of webView: WKWebView) {
            urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async { self?.updateRefreshControl(for: webView) }
            }
        }

        private func updateRefreshControl(for webView: WKWebView) {
            let path = webView.url?.path ?? "/"
            let allowed = !(path.hasPrefix("/direct") || path.hasPrefix("/reel") || path.hasPrefix("/stories"))
            let scrollView = webView.scrollView
            if allowed && scrollView.refreshControl == nil {
                let control = UIRefreshControl()
                control.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
                scrollView.refreshControl = control
            } else if !allowed && scrollView.refreshControl != nil {
                scrollView.refreshControl = nil
            }
        }

        @objc private func pullToRefresh(_ control: UIRefreshControl) {
            webView?.reload()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
        }

        // MARK: Page loaded

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            InboxChecker.syncCookies()
            webView.evaluateJavaScript("navigator.userAgent") { result, _ in
                if let userAgent = result as? String { InboxChecker.saveUserAgent(userAgent) }
            }
        }

        private let allowedHostSuffixes = [
            "instagram.com", "cdninstagram.com", "facebook.com", "fbcdn.net", "fb.com", "fbsbx.com"
        ]

        private func isAllowedHost(_ host: String?) -> Bool {
            guard let host = host?.lowercased() else { return false }
            return allowedHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            let scheme = url.scheme?.lowercased() ?? ""

            // instagram://, itms-apps://, intent:// … = attempts to open the real app or App Store.
            if scheme != "http" && scheme != "https" && scheme != "about" && scheme != "blob" && scheme != "data" {
                return decisionHandler(.cancel)
            }

            let isMainFrame = action.targetFrame?.isMainFrame ?? true
            guard isMainFrame, scheme == "http" || scheme == "https" else {
                return decisionHandler(.allow)
            }

            // The endless Reels feed -> back to the home feed.
            let path = url.path
            if isAllowedHost(url.host) && (path == "/reels" || path == "/reels/") {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: URL(string: "https://www.instagram.com/")!))
                return
            }

            // External links (and App Store links) open in Safari instead of inside the app.
            if !isAllowedHost(url.host) {
                if !(url.host ?? "").contains("apple.com") {
                    UIApplication.shared.open(url)
                }
                return decisionHandler(.cancel)
            }

            decisionHandler(.allow)
        }

        // Links that try to open a new window/tab.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url {
                if isAllowedHost(url.host) {
                    webView.load(URLRequest(url: url))
                } else if url.scheme == "http" || url.scheme == "https" {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }

        // Reload if the web content process gets killed in the background.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }
}
