import SwiftUI
@preconcurrency import WebKit

struct AuthView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .resizable()
                            .frame(width: 14, height: 22)
                            .foregroundColor(.white)
                            .padding(8)
                    }
                    Text("Sign in to Yandex")
                        .foregroundColor(.white)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

                AuthWebView(onSignedIn: onClose)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

private struct AuthWebView: UIViewRepresentable {
    let onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSignedIn: onSignedIn) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.backgroundColor = .black
        web.isOpaque = false
        var request = URLRequest(url: URL(string: "https://passport.yandex.com/auth?retpath=https%3A%2F%2Fyandex.com%2Fgames%2F")!)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        web.load(request)
        context.coordinator.startSessionWatcher(webView: web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onSignedIn: () -> Void
        private var dismissed = false
        private var watcherTask: Task<Void, Never>?

        init(onSignedIn: @escaping () -> Void) {
            self.onSignedIn = onSignedIn
        }

        deinit { watcherTask?.cancel() }

        /// Cookie-driven auth completion. Yandex's passport flow keeps
        /// changing: /pwl-yandex/auth/add (passwordless login),
        /// /webauthn-reg, /finish?, /profile/setup, /auth/welcome, etc. —
        /// chasing each dead-end URL pattern is fragile. Once Session_id is
        /// set on .yandex.com the user is authenticated regardless of which
        /// passport screen WKWebView happens to land on. Force-load /games/
        /// so `check(_:)` dismisses on the next navigation event.
        func startSessionWatcher(webView: WKWebView) {
            watcherTask?.cancel()
            watcherTask = Task { @MainActor [weak self, weak webView] in
                while let self = self, !self.dismissed, let webView = webView {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if Task.isCancelled || self.dismissed { return }
                    let cookies = await webView.configuration.websiteDataStore
                        .httpCookieStore.allCookiesAsync()
                    let sessionPresent = cookies.contains { c in
                        c.name == "Session_id" &&
                            (c.domain.hasSuffix(".yandex.com") ||
                             c.domain.hasSuffix(".yandex.ru") ||
                             c.domain == "yandex.com" ||
                             c.domain == "yandex.ru")
                    }
                    guard sessionPresent else { continue }
                    let current = webView.url?.absoluteString ?? ""
                    if !current.hasPrefix("https://yandex.com/games/") &&
                       !current.hasPrefix("https://yandex.ru/games/") {
                        webView.load(URLRequest(url: URL(string: "https://yandex.com/games/")!))
                    }
                    return
                }
            }
        }

        private func check(_ webView: WKWebView) {
            guard !dismissed, let url = webView.url?.absoluteString else { return }
            // Auto-skip webauthn registration (dead end inside WKWebView).
            if url.contains("/webauthn-reg") || url.contains("/finish?") {
                let target = URL(string: "https://yandex.com/games/")!
                webView.load(URLRequest(url: target))
                return
            }
            if url.hasPrefix("https://yandex.com/games/") || url.hasPrefix("https://yandex.ru/games/") {
                dismissed = true
                watcherTask?.cancel()
                onSignedIn()
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { check(webView) }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { check(webView) }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { check(webView) }
    }
}

private extension WKHTTPCookieStore {
    func allCookiesAsync() async -> [HTTPCookie] {
        await withCheckedContinuation { (c: CheckedContinuation<[HTTPCookie], Never>) in
            getAllCookies { c.resume(returning: $0) }
        }
    }
}
