import Foundation

struct HTTPDefaults {
    let userAgent: String
    let acceptLanguage: String

    static let ios = HTTPDefaults(
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        acceptLanguage: "en-US,en;q=0.9"
    )
}

struct YandexEndpoints {
    let platform: String
    let clientWidth: Int
    let clientHeight: Int

    init(
        platform: String = "ios",
        clientWidth: Int = 390,
        clientHeight: Int = 844
    ) {
        self.platform = platform
        self.clientWidth = clientWidth
        self.clientHeight = clientHeight
    }

    func origin() -> URL {
        URL(string: "https://\(Self.yandexHost)")!
    }

    func gamesHome() -> URL {
        URL(string: "https://\(Self.yandexHost)/games/")!
    }

    func passportOrigin() -> URL {
        URL(string: "https://passport.\(Self.yandexHost)")!
    }

    func passportAuthURL() -> URL {
        var components = URLComponents(url: passportOrigin().appendingPathComponent("auth"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "retpath", value: gamesHome().absoluteString),
        ]
        return components.url!
    }

    func feedApi() -> URL {
        URL(string: "https://\(Self.yandexHost)/games/api/catalogue/v2/feed/")!
    }

    func searchApi() -> URL {
        URL(string: "https://\(Self.yandexHost)/games/api/catalogue/v2/search/")!
    }

    func similarApi() -> URL {
        URL(string: "https://\(Self.yandexHost)/games/api/catalogue/v2/similar_games/")!
    }

    func gameDetailApi() -> URL {
        URL(string: "https://\(Self.yandexHost)/games/api/catalogue/v2/get_game")!
    }

    func tagsApi() -> URL {
        URL(string: "https://\(Self.yandexHost)/games/api/catalogue/v2/tags/")!
    }

    func userInfoApi() -> URL {
        URL(string: "https://\(Self.yandexHost)/games/api/catalogue/v2/user_info")!
    }

    func gameUrl(_ appId: Int64) -> URL {
        URL(string: "https://\(Self.yandexHost)/games/app/\(appId)")!
    }

    func isGamesUrl(_ url: String) -> Bool {
        url.hasPrefix(gamesHome().absoluteString)
    }

    func cookieOrigins() -> [String] {
        [origin().absoluteString, passportOrigin().absoluteString]
    }

    private static let yandexHost = "yandex.ru"
}

extension YandexEndpoints {
    static let live = YandexEndpoints()
}

struct AppConfig {
    let yandex: YandexEndpoints
    let http: HTTPDefaults
}

extension AppConfig {
    static func live(language: String = Locale.preferredLanguages.first ?? Locale.current.identifier) -> AppConfig {
        AppConfig(yandex: .live, http: .ios)
    }
}
