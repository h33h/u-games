import Foundation

struct YandexCatalogRemoteDataSource {
    let config: AppConfig
    let http: CatalogHTTPClient
    let parser: any CatalogParsing

    init(config: AppConfig, http: CatalogHTTPClient, parser: any CatalogParsing = YandexCatalogJsonParser()) {
        self.config = config
        self.http = http
        self.parser = parser
    }

    func fetchFeedWithBlocks(
        gamesPerPage: Int = 24,
        lang: String = "en",
        tab: String? = nil
    ) async throws -> FeedWithBlocks {
        let root = try await jsonObject(
            for: http.request(
                url: config.yandex.feedApi(),
                accept: "application/json",
                queryItems: feedQuery(
                    gamesPerPage: gamesPerPage,
                    lang: lang,
                    tab: tab,
                    blockAware: true
                )
            )
        )
        return parser.feedWithBlocks(from: root)
    }

    func fetchSearchPaginated(
        query: String,
        pageId: String? = nil,
        gamesPerPage: Int = 24,
        lang: String = "en"
    ) async throws -> FeedPage {
        let root = try await jsonObject(
            for: http.request(
                url: config.yandex.searchApi(),
                accept: "application/json",
                queryItems: compactQueryItems([
                    ("query", query),
                    ("lang", lang),
                    ("platform", config.yandex.platform),
                    ("games_count", String(gamesPerPage)),
                    ("page_id", pageId),
                ])
            )
        )
        return parser.feedPage(from: root)
    }

    func fetchCategories(lang: String = "en") async throws -> [GameCategory] {
        let root = try await jsonObject(
            for: http.request(
                url: config.yandex.tagsApi(),
                accept: "application/json",
                acceptLanguage: "ru,en;q=0.9",
                queryItems: [URLQueryItem(name: "lang", value: "ru")]
            )
        )
        return parser.categories(fromTags: root)
    }

    func fetchFeed(pageId: String?, gamesPerPage: Int = 24, lang: String = "en") async throws -> FeedPage {
        let root = try await jsonObject(
            for: http.request(
                url: config.yandex.feedApi(),
                accept: "application/json",
                queryItems: feedQuery(
                    gamesPerPage: gamesPerPage,
                    lang: lang,
                    pageId: pageId,
                    blockAware: false
                )
            )
        )
        return parser.feedPage(from: root)
    }

    func fetchAppDetail(appId: Int64, lang: String = "en") async -> AppDetail? {
        do {
            var request = http.request(
                url: config.yandex.gameDetailApi(),
                accept: "application/json",
                acceptLanguage: "ru,en;q=0.9",
                queryItems: [URLQueryItem(name: "lang", value: "ru")]
            )
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["appID": appId, "format": "app"])
            let root = try await jsonObject(for: request)
            return parser.appDetail(fromGetGame: root)
        } catch {
            return nil
        }
    }

    func fetchSimilar(appId: Int64, lang: String = "en") async -> [Game] {
        let request = http.request(
            url: config.yandex.similarApi(),
            accept: "application/json",
            queryItems: compactQueryItems([
                ("app_id", String(appId)),
                ("games_count", "16"),
                ("int", "true"),
                ("lang", lang),
                ("page_type", "game"),
                ("platform", config.yandex.platform),
                ("standalone", "false"),
            ])
        )
        do {
            let root = try await jsonObject(for: request)
            return parser.similarGames(from: root)
        } catch {
            return []
        }
    }

    func fetchSearch(query: String, lang: String = "en") async throws -> [Game] {
        let root = try await jsonObject(
            for: http.request(
                url: config.yandex.searchApi(),
                accept: "application/json",
                queryItems: compactQueryItems([
                    ("query", query),
                    ("lang", "ru"),
                    ("platform", config.yandex.platform),
                    ("games_count", "24"),
                ])
            )
        )
        return parser.feedPage(from: root).games
    }

    func fetchProfile(cookieHeader: String, lang: String = "en") async throws -> (UserProfile?, Int, Int, String) {
        var request = http.request(
            url: config.yandex.userInfoApi(),
            accept: "application/json",
            acceptLanguage: "ru,en;q=0.9",
            queryItems: [URLQueryItem(name: "lang", value: "ru")]
        )
        request.httpShouldHandleCookies = false
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await http.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (parser.userProfile(from: root), status, 0, String(data: data, encoding: .utf8) ?? "")
    }

    private func feedQuery(
        gamesPerPage: Int,
        lang: String,
        pageId: String? = nil,
        tab: String? = nil,
        blockAware: Bool
    ) -> [URLQueryItem] {
        var pairs: [(String, String?)] = [
            ("with_promos", "true"),
            ("lang", lang),
            ("games_count", String(gamesPerPage)),
            ("with_recent_games", "true"),
            ("platform", config.yandex.platform),
            ("client_width", String(config.yandex.clientWidth)),
            ("client_height", String(config.yandex.clientHeight)),
            ("page_id", pageId),
            ("tab", tab?.isEmpty == false ? tab : nil),
        ]
        if blockAware {
            pairs.append(("suggested_width", "3"))
            pairs.append(("suggested_rows", "8"))
        } else {
            pairs.append(("categorized_size", "5"))
        }
        return compactQueryItems(pairs)
    }

    private func compactQueryItems(_ pairs: [(String, String?)]) -> [URLQueryItem] {
        pairs.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
    }

    private func jsonObject(for request: URLRequest) async throws -> [String: Any] {
        let (data, _) = try await http.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
