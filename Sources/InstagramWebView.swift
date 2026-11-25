import SwiftUI
import WebKit

/// Full-screen Instagram website with Reels scrolling and "open in app" prompts removed.
struct InstagramWebView: UIViewRepresentable {
    let startURL: URL
    /// The page's background colour, so the status-bar and home-indicator areas match it.
    var onBackgroundColor: (UIColor) -> Void = { _ in }
    /// Called once, when the first page has loaded (fades out the splash screen).
    var onFirstLoad: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onBackgroundColor: onBackgroundColor, onFirstLoad: onFirstLoad)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()                 // keeps you logged in
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Look like mobile Safari so Instagram serves its normal mobile site.
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"

        let controller = config.userContentController
        controller.addUserScript(WKUserScript(source: FilterScript.source,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        controller.add(WeakScriptHandler(context.coordinator), name: "ff")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true   // swipe from the edge to go back
        webView.allowsLinkPreview = false                    // no long-press previews popping up
        webView.isOpaque = true                              // opaque views draw faster
        let background = UIColor(named: "LaunchBackground") ?? .systemBackground
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        webView.underPageBackgroundColor = background
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false

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
                webView.load(URLRequest(url: startURL))
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let onBackgroundColor: (UIColor) -> Void
        private var onFirstLoad: (() -> Void)?
        private let lightTap = UIImpactFeedbackGenerator(style: .light)
        private let mediumTap = UIImpactFeedbackGenerator(style: .medium)

        init(onBackgroundColor: @escaping (UIColor) -> Void, onFirstLoad: @escaping () -> Void) {
            self.onBackgroundColor = onBackgroundColor
            self.onFirstLoad = onFirstLoad
            super.init()
            // Never leave the splash up forever if Instagram is slow.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.finishFirstLoad() }
        }

        private func finishFirstLoad() {
            onFirstLoad?()
            onFirstLoad = nil
        }

        // MARK: Messages from the page script

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "haptic":
                lightTap.impactOccurred()
            case "refresh":
                refreshWithSpinner()
            case "background":
                if let css = body["color"] as? String, let color = UIColor(cssRGB: css) {
                    webView?.backgroundColor = color
                    webView?.scrollView.backgroundColor = color
                    webView?.underPageBackgroundColor = color
                    onBackgroundColor(color)
                }
            default:
                break
            }
        }

        // MARK: Refresh (pull down, or tap Home at the top of the feed)

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
            mediumTap.impactOccurred()
            webView?.reload()
        }

        private func refreshWithSpinner() {
            guard let webView = webView else { return }
            mediumTap.impactOccurred()
            let scrollView = webView.scrollView
            if let control = scrollView.refreshControl, !control.isRefreshing {
                control.beginRefreshing()
                let top = scrollView.adjustedContentInset.top
                scrollView.setContentOffset(CGPoint(x: 0, y: -(top + control.frame.height)), animated: true)
            }
            webView.reload()
        }

        // MARK: Page loading

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            finishFirstLoad()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            finishFirstLoad()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            finishFirstLoad()
        }

        // Reload if the web content process gets killed in the background.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        // MARK: Where links may go

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
    }
}

/// Avoids a retain cycle between the web view's content controller and the coordinator.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

extension UIColor {
    /// Parses "rgb(12, 16, 20)" or "rgba(12, 16, 20, 1)".
    convenience init?(cssRGB: String) {
        let numbers = cssRGB
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .compactMap { Double($0) }
        guard numbers.count >= 3 else { return nil }
        let alpha = numbers.count >= 4 ? numbers[3] : 1
        self.init(red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255, alpha: alpha)
    }
}
