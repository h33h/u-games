import SwiftUI
@preconcurrency import WebKit

struct GameWebView: UIViewRepresentable {
    let url: URL
    let scripts: InjectedScripts
    let blockList: BlockList

    func makeCoordinator() -> Coordinator { Coordinator(scripts: scripts) }

    /// Whether to pre-fetch the page HTML, inject our PWA chrome killers
    /// directly into <head>, and load via loadHTMLString(baseURL:). This is
    /// what the Android AdBlockingClient does, and it eliminates the
    /// "intermediate description sheet" flash before our documentStart-script
    /// CSS gets a chance to apply on a slow first paint. Falls back silently
    /// to a vanilla load() when the prefetch fails.
    private static func shouldPrefetch(_ url: URL) -> Bool {
        let s = url.absoluteString
        let isYandexGames = s.hasPrefix("https://yandex.com/games/") || s.hasPrefix("https://yandex.ru/games/")
        return isYandexGames && (s.contains("/games/app/") || s.contains("/games/play/"))
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile

        // Layer 0: log bridge. Defines window.__yga_log so the inject
        // scripts can post diagnostic events back to the native LogStore
        // via WKScriptMessageHandler. forMainFrameOnly:false so the bridge
        // is also available inside the game iframe (the SDK stub uses it).
        let logBridge = WKUserScript(
            source: """
            (function(){
              if (window.__yga_log) return;
              window.__yga_log = function(tag, msg){
                try {
                  window.webkit.messageHandlers.ugamesLog.postMessage({
                    tag: String(tag||'js'),
                    msg: String(msg==null?'':msg),
                    host: location.host,
                    path: location.pathname
                  });
                } catch(_){}
              };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(logBridge)
        config.userContentController.add(context.coordinator, name: "ugamesLog")

        // Layer 1: documentStart user scripts.
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

        // Layer 3: URL block-list compiled into WKContentRuleList.
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "ya-ads",
            encodedContentRuleList: blockList.contentRuleListJSON()
        ) { ruleList, _ in
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
        // Black background eliminates the white flash before our PWA-CSS
        // hides the catalog chrome.
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.isOpaque = false

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        if Self.shouldPrefetch(url) {
            context.coordinator.loadWithInjection(into: webView, request: request, scripts: scripts)
        } else {
            webView.load(request)
        }

        context.coordinator.attach(to: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {

        // Receives `window.__yga_log(tag, msg)` calls from the inject scripts.
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "ugamesLog" else { return }
            let tag: String
            let msg: String
            let rawMsg: String
            if let dict = message.body as? [String: Any] {
                tag = (dict["tag"] as? String) ?? "js"
                let m = (dict["msg"] as? String) ?? ""
                rawMsg = m
                let host = (dict["host"] as? String) ?? ""
                msg = host.isEmpty ? m : "[\(host)] \(m)"
            } else {
                tag = "js"
                rawMsg = String(describing: message.body)
                msg = rawMsg
            }
            Log.write(tag, msg)
            // Side-channel: when the SDK stub traps screen.orientation.lock()
            // it sends tag="orient" with the requested target string. Update
            // the global OrientationStore so GameView can show/hide the
            // rotate overlay.
            if tag == "orient" {
                Task { @MainActor in OrientationStore.shared.setFromString(rawMsg) }
            }
        }

        private weak var hostView: WKWebView?
        private var popup: WKWebView?
        private let scripts: InjectedScripts

        init(scripts: InjectedScripts) {
            self.scripts = scripts
        }

        func attach(to webView: WKWebView) {
            self.hostView = webView
        }

        /// Pre-fetch the HTML via URLSession (uses HTTPCookieStorage.shared,
        /// which SharedCookieStore mirrors from WKWebView), splice our
        /// PWA-CSS + scripts into <head>, then loadHTMLString with baseURL set
        /// to the actual page URL. This guarantees our chrome-killers apply
        /// before the first paint, mirroring AdBlockingClient on Android.
        ///
        /// On any failure (timeout, non-HTML response) we fall back to the
        /// vanilla request load — documentStart user scripts still apply, the
        /// description sheet may just briefly flash before our CSS hides it.
        func loadWithInjection(
            into webView: WKWebView,
            request: URLRequest,
            scripts: InjectedScripts
        ) {
            var prefetchRequest = request
            // identity encoding: we need to read the body unmodified to splice
            prefetchRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            prefetchRequest.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            URLSession.shared.dataTask(with: prefetchRequest) { [weak webView] data, response, _ in
                guard let webView = webView else { return }
                guard let data = data,
                      let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().contains("text/html"),
                      let html = String(data: data, encoding: .utf8)
                else {
                    DispatchQueue.main.async { webView.load(request) }
                    return
                }
                let rewritten = Self.injectIntoHead(html, scripts: scripts)
                DispatchQueue.main.async {
                    // baseURL must be the navigation URL so relative links,
                    // cookies (.yandex.com) and the page-level CSP all resolve
                    // exactly like a normal navigation.
                    webView.loadHTMLString(rewritten, baseURL: request.url)
                }
            }.resume()
        }

        private static func injectIntoHead(_ html: String, scripts: InjectedScripts) -> String {
            let style = "<style id=\"__yga_pwa__\">\(scripts.pwaModeCss)</style>"
            let cssLiteral = jsString(scripts.pwaModeCss)
            let script = "<script id=\"__yga_inject__\">window.__yga_pwa_css_payload__=\(cssLiteral);\(scripts.honestPath);\(scripts.pwaModeJs)</script>"
            let payload = style + script
            // Insert immediately after the opening <head ...> tag.
            guard let headRange = html.range(of: "<head", options: .caseInsensitive),
                  let openIdx = html.range(of: ">", range: headRange.upperBound..<html.endIndex)
            else {
                return payload + html
            }
            return String(html[html.startIndex..<openIdx.upperBound]) + payload + String(html[openIdx.upperBound..<html.endIndex])
        }

        private static func jsString(_ value: String) -> String {
            var out = "\""
            for char in value.unicodeScalars {
                switch char.value {
                case 0x5C: out.append("\\\\")
                case 0x22: out.append("\\\"")
                case 0x0A: out.append("\\n")
                case 0x0D: out.append("\\r")
                case 0x09: out.append("\\t")
                case 0x2028: out.append("\\u2028")
                case 0x2029: out.append("\\u2029")
                default: out.append(Character(char))
                }
            }
            out.append("\"")
            return out
        }

        // Layer 2: belt-and-braces re-injection at navigation milestones, in
        // case the documentStart script registration didn't apply in time
        // (older WebKit, race with React boot).
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Log.write("nav", "start \(webView.url?.absoluteString ?? "?")")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Log.write("nav", "commit \(webView.url?.absoluteString ?? "?")")
            reinject(in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Log.write("nav", "finish \(webView.url?.absoluteString ?? "?")")
            reinject(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Log.write("nav", "fail \((error as NSError).code) \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Log.write("nav", "failProv \((error as NSError).code) \(error.localizedDescription)")
        }

        private func reinject(in webView: WKWebView) {
            guard let url = webView.url?.absoluteString else { return }
            if url.hasPrefix("https://yandex.com/games") || url.hasPrefix("https://yandex.ru/games") {
                webView.evaluateJavaScript(scripts.mainFrameScript, completionHandler: nil)
            }
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
