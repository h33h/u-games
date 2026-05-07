import Foundation
import WebKit

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
