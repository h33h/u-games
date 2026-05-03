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
}

extension SharedCookieStore: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        copyFromWebToShared()
    }
}
