import SwiftUI
@preconcurrency import WebKit

@MainActor
final class AuthState: ObservableObject {
    @Published var isLoading: Bool = true
    @Published var loadError: String?
    @Published var reloadToken: Int = 0

    func retry() {
        loadError = nil
        isLoading = true
        reloadToken &+= 1
    }
}

struct AuthView: View {
    let onClose: () -> Void

    @StateObject private var state = AuthState()

    var body: some View {
        ZStack(alignment: .topLeading) {
            UGColor.Surface.base.ignoresSafeArea()
            VStack(spacing: 0) {
                UGTopBar(title: "Sign in to Yandex", onBack: onClose)
                ZStack {
                    AuthWebView(state: state, onSignedIn: onClose)
                        .ignoresSafeArea(edges: .bottom)
                    if let err = state.loadError {
                        AuthErrorOverlay(message: err, onRetry: { state.retry() })
                    } else if state.isLoading {
                        AuthLoadingOverlay()
                    }
                }
            }
        }
    }
}

private struct AuthLoadingOverlay: View {
    var body: some View {
        ZStack {
            UGColor.Surface.base.ignoresSafeArea()
            VStack(spacing: UGSpace.l) {
                ProgressView()
                    .tint(UGColor.Text.primary)
                    .scaleEffect(1.4)
                Text("Signing in via Yandex Passport…")
                    .font(UGFont.bodyS)
                    .foregroundColor(UGColor.Text.secondary)
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signing in")
    }
}

private struct AuthErrorOverlay: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            UGColor.Surface.base.ignoresSafeArea()
            EmptyState(
                systemIcon: "wifi.slash",
                title: "Couldn't sign in",
                message: message,
                ctaLabel: "Try again",
                onCta: onRetry
            )
        }
        .transition(.opacity)
    }
}

private struct AuthWebView: UIViewRepresentable {
    @ObservedObject var state: AuthState
    let onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onSignedIn: onSignedIn)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webViewConfig = WKWebViewConfiguration()
        webViewConfig.websiteDataStore = .default()

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
        webViewConfig.userContentController.addUserScript(logBridge)
        webViewConfig.userContentController.add(context.coordinator, name: "ugamesLog")

        let web = WKWebView(frame: .zero, configuration: webViewConfig)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.backgroundColor = .black
        web.isOpaque = false
        Log.write("auth", "AuthView opened: passportHost=passport.yandex.ru retpath=https://yandex.ru/games/ gamesHost=yandex.ru")
        web.load(URLRequest(url: URL(string: "https://passport.yandex.ru/auth?retpath=https%3A%2F%2Fyandex.ru%2Fgames%2F")!))
        context.coordinator.startSessionWatcher(webView: web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if state.reloadToken != context.coordinator.lastReloadToken {
            context.coordinator.lastReloadToken = state.reloadToken
            context.coordinator.firstLoadDone = false
            uiView.load(URLRequest(url: URL(string: "https://passport.yandex.ru/auth?retpath=https%3A%2F%2Fyandex.ru%2Fgames%2F")!))
            Log.write("auth", "manual retry reload token=\(state.reloadToken)")
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let state: AuthState
        let onSignedIn: () -> Void
        private var dismissed = false
        private var watcherTask: Task<Void, Never>?
        var firstLoadDone = false
        var lastReloadToken: Int = 0

        init(state: AuthState, onSignedIn: @escaping () -> Void) {
            self.state = state
            self.onSignedIn = onSignedIn
        }

        deinit { watcherTask?.cancel() }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "ugamesLog" else { return }
            let tag: String
            let msg: String
            if let dict = message.body as? [String: Any] {
                tag = (dict["tag"] as? String) ?? "js"
                let m = (dict["msg"] as? String) ?? ""
                let host = (dict["host"] as? String) ?? ""
                msg = host.isEmpty ? m : "[\(host)] \(m)"
            } else {
                tag = "js"
                msg = String(describing: message.body)
            }
            Log.write(tag, msg)
        }

        func startSessionWatcher(webView: WKWebView) {
            watcherTask?.cancel()
            Log.write("auth", "Session_id watcher started (poll=400ms)")
            watcherTask = Task { @MainActor [weak self, weak webView] in
                var ticks = 0
                while let self = self, !self.dismissed, let webView = webView {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if Task.isCancelled || self.dismissed { return }
                    ticks += 1
                    let cookies = await webView.configuration.websiteDataStore
                        .httpCookieStore.allCookiesAsync()
                    let yandexCookies = cookies.filter {
                        $0.domain.contains("yandex.ru")
                    }

                    let sessionPresent = yandexCookies.contains { c in
                        c.name == "Session_id" && c.domain.contains("yandex.ru")
                    }
                    if ticks % 5 == 0 {
                        let names = yandexCookies.map { "\($0.name)@\($0.domain)" }.sorted().joined(separator: ",")
                        Log.write("cookie", "tick=\(ticks) waiting for Session_id@yandex.ru; have \(yandexCookies.count): \(names)")
                    }
                    guard sessionPresent else { continue }
                    let current = webView.url?.absoluteString ?? ""
                    Log.write("auth", "Session_id detected after \(ticks*400)ms; current=\(current)")
                    let target = URL(string: "https://yandex.ru/games/")!
                    if !current.hasPrefix("https://yandex.ru/games/") {
                        Log.write("auth", "force-loading \(target.absoluteString)")
                        webView.load(URLRequest(url: target))
                    }

                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if Task.isCancelled || self.dismissed { return }
                    self.dismissed = true
                    let finalURL = webView.url?.absoluteString ?? "?"
                    let postCookies = await webView.configuration.websiteDataStore
                        .httpCookieStore.allCookiesAsync()
                    let yandexSessions = postCookies.filter { $0.domain.contains(".yandex.ru") && $0.name == "Session_id" }.count
                    Log.write("auth", "post-grace dismiss; finalURL=\(finalURL) yandexSessions=\(yandexSessions)")
                    self.onSignedIn()
                    return
                }
            }
        }

        private func check(_ webView: WKWebView) {
            guard !dismissed, let url = webView.url?.absoluteString else { return }
            if url.contains("/webauthn-reg") || url.contains("/finish?") {
                Log.write("auth", "skip dead-end \(url)")
                webView.load(URLRequest(url: URL(string: "https://yandex.ru/games/")!))
                return
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Log.write("nav", "auth commit \(webView.url?.absoluteString ?? "?")")
            if !firstLoadDone {
                Task { @MainActor in self.state.isLoading = false }
            }
            check(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Log.write("nav", "auth finish \(webView.url?.absoluteString ?? "?")")
            firstLoadDone = true
            Task { @MainActor in
                self.state.isLoading = false
                self.state.loadError = nil
            }
            check(webView)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Log.write("nav", "auth start \(webView.url?.absoluteString ?? "?")")
            if !firstLoadDone {
                Task { @MainActor in self.state.isLoading = true }
            }
            check(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Log.write("nav", "auth fail \((error as NSError).code) \(error.localizedDescription)")
            if !firstLoadDone {
                let message = error.localizedDescription
                Task { @MainActor in
                    self.state.isLoading = false
                    self.state.loadError = message
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Log.write("nav", "auth failProv \((error as NSError).code) \(error.localizedDescription)")
            let nsErr = error as NSError
            // -999 (NSURLErrorCancelled) is a transient cancel during nav redirects — ignore.
            if !firstLoadDone, nsErr.code != NSURLErrorCancelled {
                let message = error.localizedDescription
                Task { @MainActor in
                    self.state.isLoading = false
                    self.state.loadError = message
                }
            }
        }
    }
}

private extension WKHTTPCookieStore {
    func allCookiesAsync() async -> [HTTPCookie] {
        await withCheckedContinuation { (c: CheckedContinuation<[HTTPCookie], Never>) in
            getAllCookies { c.resume(returning: $0) }
        }
    }
}
