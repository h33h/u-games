import Foundation

struct YandexCatalogRemoteDataSource {
    let config: AppConfig
    let http: CatalogHTTPClient

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
        return CatalogFeedParser.feedWithBlocks(from: root)
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
        return CatalogFeedParser.feedPage(from: root)
    }

    func fetchCategories(lang: String = "en") async throws -> [GameCategory] {
        let host = config.yandex.preferredHost
        let preferredLang = effectiveLang(host: host, requested: lang)
        let request = http.request(
            url: config.yandex.gamesHome(host),
            accept: "text/html",
            acceptLanguage: "\(preferredLang),en;q=0.9",
            queryItems: [URLQueryItem(name: "lang", value: preferredLang)]
        )
        let (data, _) = try await http.data(for: request)
        guard let html = String(data: data, encoding: .utf8),
              let json = CatalogHtmlParser.extractAppData(html)
        else { return [] }
        return CatalogHtmlParser.categories(fromAppData: json)
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
        return CatalogFeedParser.feedPage(from: root)
    }

    func fetchAppDetail(appId: Int64, lang: String = "en") async -> AppDetail? {
        let host = config.yandex.preferredHost
        let preferredLang = effectiveLang(host: host, requested: lang)
        let request = http.request(
            url: config.yandex.gameUrl(appId, host: host),
            accept: "text/html",
            acceptLanguage: "\(preferredLang),en;q=0.9",
            queryItems: [URLQueryItem(name: "lang", value: preferredLang)]
        )
        do {
            let (data, _) = try await http.data(for: request)
            guard let html = String(data: data, encoding: .utf8),
                  let ldJson = CatalogHtmlParser.extractJsonLd(html)
            else { return nil }
            return CatalogHtmlParser.appDetail(fromJsonLd: ldJson)
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
            return CatalogFeedParser.similarGames(from: root)
        } catch {
            return []
        }
    }

    func fetchSearch(query: String, lang: String = "en") async throws -> [Game] {
        let request = http.request(
            url: config.yandex.searchPage(),
            accept: "text/html,application/xhtml+xml",
            queryItems: compactQueryItems([("query", query), ("lang", lang)])
        )
        let (data, _) = try await http.data(for: request)
        guard let html = String(data: data, encoding: .utf8),
              let json = CatalogHtmlParser.extractAppData(html),
              let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let search = parsed["search"] as? [String: Any],
              let blocks = search["data"] as? [[String: Any]]
        else { return [] }
        return GameDecoder.flatten(blocks)
    }

    func fetchProfile(cookieHeader: String, lang: String = "en") async throws -> (UserProfile?, Int, Int, String) {
        let host = config.yandex.preferredHost
        let preferredLang = effectiveLang(host: host, requested: lang)
        var request = http.request(
            url: config.yandex.gamesHome(host),
            accept: "text/html",
            acceptLanguage: "\(preferredLang),en;q=0.9",
            queryItems: [URLQueryItem(name: "lang", value: preferredLang)]
        )
        request.httpShouldHandleCookies = false
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        let delegate = ProfileFetchRedirectDelegate(cookieHeader: cookieHeader)
        let (data, response) = try await URLSession.shared.data(for: request, delegate: delegate)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard let html = String(data: data, encoding: .utf8),
              let json = CatalogHtmlParser.extractAppData(html)
        else { return (nil, status, delegate.redirectCount, "") }
        return (CatalogHtmlParser.userProfile(fromAppData: json), status, delegate.redirectCount, html)
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

    private func effectiveLang(host: YandexHost, requested: String) -> String {
        host == .ru ? "ru" : requested
    }
}
