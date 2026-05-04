import Foundation
import WebKit

/// Bridges WKWebView's WKHTTPCookieStore to URLSession's HTTPCookieStorage so
/// that catalog HTTP requests share the same session as the in-app WebView
/// (game iframe, auth screen). Without this, signing in via the auth WebView
/// wouldn't be visible to /games/ HTML fetch and the user would appear
/// anonymous to our profile loader.
final class SharedCookieStore: NSObject, @unchecked Sendable {
    static let shared = SharedCookieStore()

    private let webStore: WKHTTPCookieStore
    private let sharedStorage: HTTPCookieStorage

    private override init() {
        self.webStore = WKWebsiteDataStore.default().httpCookieStore
        self.sharedStorage = HTTPCookieStorage.shared
        super.init()
        sharedStorage.cookieAcceptPolicy = .always
        webStore.add(self)
        // Initial copy WK -> shared so any persisted cookies become visible
        // to URLSession before the first request.
        copyFromWebToShared()
    }

    func copyFromWebToShared() {
        webStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            for cookie in cookies {
                self.sharedStorage.setCookie(cookie)
            }
        }
    }

    /// Awaitable variant of `copyFromWebToShared`. Resolves after every cookie
    /// currently in WKHTTPCookieStore has been mirrored into HTTPCookieStorage.
    /// Use this before issuing a URLSession request that depends on the latest
    /// authenticated session — the observer-driven mirror is async and may not
    /// yet have copied a Session_id set during a redirect chain that just
    /// finished in WKWebView.
    func syncToShared() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            webStore.getAllCookies { [weak self] cookies in
                guard let self = self else { c.resume(); return }
                for cookie in cookies {
                    self.sharedStorage.setCookie(cookie)
                }
                c.resume()
            }
        }
    }

    /// Used by "Sign out": drops every Yandex cookie from both stores so the
    /// next request to `yandex.com/games/` is anonymous again.
    func clearYandexCookies() async {
        for cookie in sharedStorage.cookies ?? [] where cookie.domain.contains("yandex") {
            sharedStorage.deleteCookie(cookie)
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            webStore.getAllCookies { [weak self] cookies in
                guard let self = self else { c.resume(); return }
                let yandexCookies = cookies.filter { $0.domain.contains("yandex") }
                if yandexCookies.isEmpty { c.resume(); return }
                var remaining = yandexCookies.count
                for cookie in yandexCookies {
                    self.webStore.delete(cookie) {
                        remaining -= 1
                        if remaining == 0 { c.resume() }
                    }
                }
            }
        }
    }
}

extension SharedCookieStore: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        copyFromWebToShared()
    }
}
