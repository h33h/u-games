package games.yandex.wrap.catalog

import games.yandex.wrap.config.AppConfig
import games.yandex.wrap.config.YandexHost

class CatalogApi(
    private val http: YandexHttpClient,
    private val jsonParser: CatalogJsonParser,
    private val htmlParser: CatalogHtmlParser,
    private val sessionStore: YandexSessionStore,
    private val config: AppConfig,
) {
    private val endpoints = config.yandex

    suspend fun firstFeedPage(
        gamesPerPage: Int = 24,
        lang: String = "en",
        clientWidth: Int = endpoints.clientWidth,
        clientHeight: Int = endpoints.clientHeight,
    ): FeedPage = fetchFeed(
        pageId = null,
        gamesPerPage = gamesPerPage,
        lang = lang,
        clientWidth = clientWidth,
        clientHeight = clientHeight,
    )

    suspend fun firstFeedPageWithBlocks(
        gamesPerPage: Int = 24,
        lang: String = "en",
        clientWidth: Int = endpoints.clientWidth,
        clientHeight: Int = endpoints.clientHeight,
        tab: String? = null,
    ): FeedWithBlocks {
        val response = http.getJson(
            endpoints.feedApi(),
            query = mapOf(
                "with_promos" to "true",
                "lang" to lang,
                "games_count" to gamesPerPage.toString(),
                "suggested_width" to "3",
                "suggested_rows" to "8",
                "with_recent_games" to "true",
                "platform" to endpoints.platform,
                "client_width" to clientWidth.toString(),
                "client_height" to clientHeight.toString(),
                "tab" to tab?.takeIf { it.isNotEmpty() },
            ),
        )
        return jsonParser.feedWithBlocks(response)
    }

    suspend fun searchPaginated(
        query: String,
        pageId: String? = null,
        gamesPerPage: Int = 24,
        lang: String = "en",
    ): FeedPage {
        if (query.isBlank()) return FeedPage(emptyList(), null, false)
        val response = http.getJson(
            endpoints.searchApi(),
            query = mapOf(
                "query" to query,
                "lang" to lang,
                "platform" to endpoints.platform,
                "games_count" to gamesPerPage.toString(),
                "page_id" to pageId,
            ),
        )
        return jsonParser.feedPage(response)
    }

    suspend fun fetchCategories(lang: String = "en"): List<GameCategory> {
        val host = sessionStore.preferredYandexHost()
        val effectiveLang = effectiveLang(host, lang)
        val html = runCatching {
            http.getHtml(
                endpoints.gamesHome(host),
                query = mapOf("lang" to effectiveLang),
                acceptLanguage = "$effectiveLang,en;q=0.9",
            )
        }.getOrElse { return emptyList() }
        val appData = htmlParser.extractAppData(html) ?: return emptyList()
        return htmlParser.categoriesFromAppData(appData)
    }

    suspend fun nextFeedPage(
        pageId: String,
        gamesPerPage: Int = 24,
        lang: String = "en",
        clientWidth: Int = endpoints.clientWidth,
        clientHeight: Int = endpoints.clientHeight,
    ): FeedPage = fetchFeed(
        pageId = pageId,
        gamesPerPage = gamesPerPage,
        lang = lang,
        clientWidth = clientWidth,
        clientHeight = clientHeight,
    )

    private suspend fun fetchFeed(
        pageId: String?,
        gamesPerPage: Int,
        lang: String,
        clientWidth: Int,
        clientHeight: Int,
    ): FeedPage {
        val response = http.getJson(
            endpoints.feedApi(),
            query = mapOf(
                "with_promos" to "true",
                "lang" to lang,
                "games_count" to gamesPerPage.toString(),
                "categorized_size" to "5",
                "with_recent_games" to "true",
                "platform" to endpoints.platform,
                "client_width" to clientWidth.toString(),
                "client_height" to clientHeight.toString(),
                "page_id" to pageId,
            ),
        )
        return jsonParser.feedPage(response)
    }

    suspend fun appDetail(appId: Long, lang: String = "en"): AppDetail? {
        val host = sessionStore.preferredYandexHost()
        val effectiveLang = effectiveLang(host, lang)
        val html = runCatching {
            http.getHtml(
                endpoints.gameUrl(appId, host),
                query = mapOf("lang" to effectiveLang),
                acceptLanguage = "$effectiveLang,en;q=0.9",
            )
        }.getOrElse { return null }
        val ldJson = htmlParser.extractJsonLd(html) ?: return null
        return htmlParser.appDetailFromJsonLd(ldJson)
    }

    suspend fun similar(appId: Long, lang: String = "en"): List<Game> {
        val response = http.getJson(
            endpoints.similarApi(),
            query = mapOf(
                "app_id" to appId.toString(),
                "games_count" to "16",
                "int" to "true",
                "lang" to lang,
                "page_type" to "game",
                "platform" to endpoints.platform,
                "standalone" to "false",
            ),
        )
        return jsonParser.similarGames(response)
    }

    suspend fun search(query: String, lang: String = "en"): List<Game> {
        if (query.isBlank()) return emptyList()
        val html = http.getHtml(
            endpoints.searchPage(),
            query = mapOf("query" to query, "lang" to lang),
            accept = "text/html,application/xhtml+xml",
        )
        val appData = htmlParser.extractAppData(html) ?: return emptyList()
        return htmlParser.searchGamesFromAppData(appData)
    }

    suspend fun userProfile(lang: String = "en"): UserProfile? {
        val host = sessionStore.preferredYandexHost()
        val effectiveLang = effectiveLang(host, lang)
        val html = runCatching {
            http.getHtml(
                endpoints.gamesHome(host),
                query = mapOf("lang" to effectiveLang),
                acceptLanguage = "$effectiveLang,en;q=0.9",
                cookieHeader = sessionStore.buildMergedYandexCookieHeader(),
            )
        }.getOrElse { return null }
        val appData = htmlParser.extractAppData(html) ?: return null
        return htmlParser.profileFromAppData(appData)
    }

    private fun effectiveLang(host: YandexHost, requested: String): String =
        if (host == YandexHost.Ru) "ru" else requested
}
