import Foundation

enum GameNavigationPolicy {
    static func allowsFrame(_ url: URL, source: URL?) -> Bool {
        if url.absoluteString == "about:srcdoc" {
            return true
        }
        if allows(url) {
            return true
        }
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased()
        else { return false }
        if host.hasSuffix(".games.yandex.net") || host.hasSuffix(".games.s3.yandex.net") {
            return true
        }
        guard let source = source else { return false }
        return source.scheme == url.scheme && source.host?.lowercased() == host &&
            (source.port ?? 443) == (url.port ?? 443) &&
            ![
                "yandex.ru",
                "www.yandex.ru",
                "yandex.com",
                "www.yandex.com",
                "passport.yandex.ru",
                "passport.yandex.com",
                "sso.passport.yandex.ru",
                "sso.passport.yandex.com",
                "sso.ya.ru",
            ].contains(host)
    }

    static func allows(_ url: URL) -> Bool {
        if url.absoluteString == "about:blank" {
            return true
        }
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased()
        else { return false }
        let path = url.path
        if ["yandex.ru", "www.yandex.ru", "yandex.com", "www.yandex.com"].contains(host) {
            return path == "/games" || path.hasPrefix("/games/")
        }
        if ["passport.yandex.ru", "passport.yandex.com"].contains(host) {
            return ["/auth", "/registration", "/pwl-yandex"]
                .contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        if ["sso.passport.yandex.ru", "sso.passport.yandex.com"].contains(host) {
            return path == "/prepare" || path == "/prepare/"
        }
        if host == "sso.ya.ru" {
            return path == "/sync" || path == "/sync/"
        }
        return false
    }
}
