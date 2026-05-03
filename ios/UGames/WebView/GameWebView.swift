import SwiftUI
@preconcurrency import WebKit

struct GameWebView: UIViewRepresentable {
    let url: URL
    let scripts: InjectedScripts
    let blockList: BlockList

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile

        let mainScript = WKUserScript(
            source: scripts.mainFrameScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        let stubScript = WKUserScript(
            source: scripts.sdkStub,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(mainScript)
        config.userContentController.addUserScript(stubScript)

        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "ya-ads",
            encodedContentRuleList: blockList.contentRuleListJSON()
        ) { ruleList, error in
            if let ruleList = ruleList {
                config.userContentController.add(ruleList)
            }
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = .black
        webView.isOpaque = false

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        webView.load(request)

        context.coordinator.attach(to: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        private weak var hostView: WKWebView?
        private var popup: WKWebView?

        func attach(to webView: WKWebView) {
            self.hostView = webView
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            let popup = WKWebView(frame: webView.bounds, configuration: configuration)
            popup.uiDelegate = self
            popup.navigationDelegate = self
            popup.translatesAutoresizingMaskIntoConstraints = false
            self.popup = popup
            webView.addSubview(popup)
            NSLayoutConstraint.activate([
                popup.topAnchor.constraint(equalTo: webView.topAnchor),
                popup.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
                popup.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                popup.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            ])
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            webView.removeFromSuperview()
            if webView === popup { popup = nil }
        }
    }
}
