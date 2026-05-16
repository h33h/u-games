import Foundation

struct YandexSessionStore {
    let config: AppConfig

    func waitForSessionCookie(timeoutSeconds: TimeInterval) async -> String {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let yandex = config.yandex.origin(config.yandex.preferredHost)
        var ticks = 0
        while Date() < deadline {
            let cookies = HTTPCookieStorage.shared.cookies(for: yandex) ?? []
            if cookies.contains(where: { $0.name == "Session_id" }) {
                let names = cookies.map { $0.name }.sorted().joined(separator: ",")
                return "found after \(ticks * 150)ms (cookies=\(cookies.count) names=\(names))"
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            ticks += 1
        }
        let cookies = HTTPCookieStorage.shared.cookies(for: yandex) ?? []
        let names = cookies.map { $0.name }.sorted().joined(separator: ",")
        return "TIMEOUT after \(Int(timeoutSeconds * 1000))ms (cookies=\(cookies.count) names=\(names))"
    }

    func mergedYandexCookieHeader() -> (header: String, names: String, count: Int) {
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        let donors = config.yandex.cookieDonorOrigins()
        let yandexCookies = allCookies.filter { cookie in
            donors.contains { donor in cookie.domain.contains(URL(string: donor)!.host ?? "") }
        }
        var dedup: [String: HTTPCookie] = [:]
        for cookie in yandexCookies { dedup[cookie.name] = cookie }
        let header = dedup.values.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        return (header, dedup.keys.sorted().joined(separator: ","), dedup.count)
    }

    func clearSession() async {
        let store = HTTPCookieStorage.shared
        for cookie in store.cookies ?? [] {
            if cookie.domain.contains("yandex") {
                store.deleteCookie(cookie)
            }
        }
        await SharedCookieStore.shared.clearYandexCookies()
    }
}

final class ProfileFetchRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let cookieHeader: String
    private(set) var redirectCount: Int = 0

    init(cookieHeader: String) { self.cookieHeader = cookieHeader }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirectCount += 1
        var modified = request
        modified.httpShouldHandleCookies = false
        if !cookieHeader.isEmpty {
            modified.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        completionHandler(modified)
    }
}
