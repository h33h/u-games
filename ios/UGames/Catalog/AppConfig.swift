import Foundation

enum YandexHost: String {
    case com = "yandex.com"
    case ru = "yandex.ru"
}

struct HTTPDefaults {
    let userAgent: String
    let acceptLanguage: String

    static let ios = HTTPDefaults(
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        acceptLanguage: "en-US,en;q=0.9"
    )
}

struct YandexEndpoints {
    let preferredHost: YandexHost
    let apiHost: YandexHost
    let platform: String
    let clientWidth: Int
    let clientHeight: Int

    init(
        preferredHost: YandexHost,
        apiHost: YandexHost = .com,
        platform: String = "ios",
        clientWidth: Int = 390,
        clientHeight: Int = 844
    ) {
        self.preferredHost = preferredHost
        self.apiHost = apiHost
        self.platform = platform
        self.clientWidth = clientWidth
        self.clientHeight = clientHeight
    }

    func origin(_ host: YandexHost? = nil) -> URL {
        URL(string: "https://\((host ?? preferredHost).rawValue)")!
    }

    func gamesHome(_ host: YandexHost? = nil) -> URL {
        URL(string: "https://\((host ?? preferredHost).rawValue)/games/")!
    }

    func passportOrigin() -> URL {
        URL(string: preferredHost == .ru ? "https://passport.yandex.ru" : "https://passport.yandex.com")!
    }

    func passportAuthURL() -> URL {
        var components = URLComponents(url: passportOrigin().appendingPathComponent("auth"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "retpath", value: gamesHome().absoluteString),
        ]
        return components.url!
    }

    func feedApi() -> URL {
        URL(string: "https://\(apiHost.rawValue)/games/api/catalogue/v2/feed/")!
    }

    func searchApi() -> URL {
        URL(string: "https://\(apiHost.rawValue)/games/api/catalogue/v2/search/")!
    }

    func similarApi() -> URL {
        URL(string: "https://\(apiHost.rawValue)/games/api/catalogue/v2/similar_games/")!
    }

    func searchPage() -> URL {
        URL(string: "https://\(apiHost.rawValue)/games/search")!
    }

    func gameUrl(_ appId: Int64, host: YandexHost? = nil) -> URL {
        URL(string: "https://\((host ?? apiHost).rawValue)/games/app/\(appId)")!
    }

    func isGamesUrl(_ url: String) -> Bool {
        url.hasPrefix(gamesHome(.com).absoluteString) || url.hasPrefix(gamesHome(.ru).absoluteString)
    }

    func cookieDonorOrigins() -> [String] {
        [
            origin(.com).absoluteString,
            origin(.ru).absoluteString,
            "https://passport.yandex.com",
            "https://passport.yandex.ru",
        ]
    }
}

struct AppConfig {
    let yandex: YandexEndpoints
    let http: HTTPDefaults

    static func live(language: String = Locale.preferredLanguages.first ?? Locale.current.identifier) -> AppConfig {
        let preferred: YandexHost = language.hasPrefix("ru") ? .ru : .com
        return AppConfig(yandex: YandexEndpoints(preferredHost: preferred), http: .ios)
    }
}
