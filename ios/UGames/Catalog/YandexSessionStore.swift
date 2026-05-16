import Foundation

struct YandexSessionStore {
    let config: AppConfig

    func sessionCookieHeader(timeoutSeconds: TimeInterval = 3.0) async -> (header: String, names: String, count: Int) {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let header = cookieHeader()
            if header.names.contains("Session_id") {
                return header
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return cookieHeader()
    }

    private func cookieHeader() -> (header: String, names: String, count: Int) {
        let origins = config.yandex.cookieOrigins().compactMap(URL.init(string:))
        let yandexCookies = origins.flatMap { HTTPCookieStorage.shared.cookies(for: $0) ?? [] }
        var dedup: [String: HTTPCookie] = [:]
        for cookie in yandexCookies { dedup[cookie.name] = cookie }
        let header = dedup.values.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        return (header, dedup.keys.sorted().joined(separator: ","), dedup.count)
    }

    func clearSession() async {
        let store = HTTPCookieStorage.shared
        for cookie in store.cookies ?? [] {
            if cookie.domain.contains("yandex.ru") {
                store.deleteCookie(cookie)
            }
        }
        await SharedCookieStore.shared.clearYandexCookies()
    }
}
