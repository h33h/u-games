package games.yandex.wrap.catalog

import games.yandex.wrap.catalog.models.AppDetail
import games.yandex.wrap.catalog.models.FeedPage
import games.yandex.wrap.catalog.models.FeedWithBlocks
import games.yandex.wrap.catalog.models.Game
import games.yandex.wrap.catalog.models.GameCategory
import games.yandex.wrap.catalog.models.UserProfile
import games.yandex.wrap.config.AppConfig
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

class CatalogApi(
    private val http: YandexHttpClient,
    private val parser: CatalogParser,
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
        return parser.feedWithBlocks(response)
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
        return parser.feedPage(response)
    }

    suspend fun fetchCategories(lang: String = "en"): List<GameCategory> {
        val response = runCatching {
            http.getJson(
                endpoints.tagsApi(),
                query = mapOf("lang" to "ru"),
                acceptLanguage = "ru,en;q=0.9",
            )
        }.getOrElse { return emptyList() }
        return parser.categoriesFromTags(response)
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
        return parser.feedPage(response)
    }

    suspend fun appDetail(appId: Long, lang: String = "en"): AppDetail? {
        val response = runCatching {
            http.postJson(
                endpoints.gameDetailApi(),
                body = buildJsonObject {
                    put("appID", JsonPrimitive(appId))
                    put("format", JsonPrimitive("app"))
                },
                query = mapOf("lang" to "ru"),
                acceptLanguage = "ru,en;q=0.9",
            )
        }.getOrElse { return null }
        return parser.appDetail(response)
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
        return parser.similarGames(response)
    }

    suspend fun search(query: String, lang: String = "en"): List<Game> {
        if (query.isBlank()) return emptyList()
        val response = http.getJson(
            endpoints.searchApi(),
            query = mapOf(
                "query" to query,
                "lang" to "ru",
                "platform" to endpoints.platform,
                "games_count" to "24",
            ),
        )
        return parser.feedPage(response).games
    }

    suspend fun userProfile(lang: String = "en"): UserProfile? {
        val cookieHeader = sessionStore.sessionCookieHeader()
        if (cookieHeader.isBlank()) return null
        val response = runCatching {
            http.getJson(
                endpoints.userInfoApi(),
                query = mapOf("lang" to "ru"),
                acceptLanguage = "ru,en;q=0.9",
                cookieHeader = cookieHeader,
            )
        }.getOrElse { return null }
        return parser.profile(response)
    }
}
