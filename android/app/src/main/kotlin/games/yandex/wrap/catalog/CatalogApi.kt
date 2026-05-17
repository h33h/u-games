package games.yandex.wrap.catalog

import games.yandex.wrap.catalog.models.AppDetail
import games.yandex.wrap.catalog.models.FeedPage
import games.yandex.wrap.catalog.models.FeedWithBlocks
import games.yandex.wrap.catalog.models.Game
import games.yandex.wrap.catalog.models.GameCategory
import games.yandex.wrap.catalog.models.UserProfile
import games.yandex.wrap.network.FeedEndpointService
import games.yandex.wrap.network.GameDetailEndpointService
import games.yandex.wrap.network.SearchEndpointService
import games.yandex.wrap.network.SimilarGamesEndpointService
import games.yandex.wrap.network.TagsEndpointService
import games.yandex.wrap.network.UserInfoEndpointService

class CatalogApi(
    private val feedEndpoint: FeedEndpointService,
    private val searchEndpoint: SearchEndpointService,
    private val tagsEndpoint: TagsEndpointService,
    private val gameDetailEndpoint: GameDetailEndpointService,
    private val similarGamesEndpoint: SimilarGamesEndpointService,
    private val userInfoEndpoint: UserInfoEndpointService,
) {
    suspend fun firstFeedPage(
        gamesPerPage: Int = 24,
    ): FeedPage = fetchFeed(
        pageId = null,
        gamesPerPage = gamesPerPage,
    )

    suspend fun firstFeedPageWithBlocks(
        gamesPerPage: Int = 24,
        tab: String? = null,
    ): FeedWithBlocks = feedEndpoint.feed(
        gamesPerPage = gamesPerPage,
        tab = tab,
    ).toFeedWithBlocks()

    suspend fun searchPaginated(
        query: String,
        pageId: String? = null,
        gamesPerPage: Int = 24,
    ): FeedPage {
        if (query.isBlank()) return FeedPage(emptyList(), null, false)
        return searchEndpoint.search(
            query = query,
            pageId = pageId,
            gamesPerPage = gamesPerPage,
        ).toFeedPage()
    }

    suspend fun fetchCategories(): List<GameCategory> =
        runCatching { tagsEndpoint.tags().toCategories() }.getOrElse { emptyList() }

    suspend fun nextFeedPage(
        pageId: String,
        gamesPerPage: Int = 24,
        tab: String? = null,
    ): FeedPage = fetchFeed(
        pageId = pageId,
        gamesPerPage = gamesPerPage,
        tab = tab,
    )

    private suspend fun fetchFeed(
        pageId: String?,
        gamesPerPage: Int,
        tab: String? = null,
    ): FeedPage = feedEndpoint.feed(
        gamesPerPage = gamesPerPage,
        pageId = pageId,
        tab = tab,
    ).toFeedPage()

    suspend fun appDetail(appId: Long): AppDetail? =
        runCatching { gameDetailEndpoint.detail(appId).toAppDetail() }.getOrElse { null }

    suspend fun similar(appId: Long): List<Game> =
        similarGamesEndpoint.similar(appId).toGames()

    suspend fun search(query: String): List<Game> {
        if (query.isBlank()) return emptyList()
        return searchEndpoint.search(
            query = query,
            gamesPerPage = 24,
        ).toFeedPage().games
    }

    suspend fun userProfile(): UserProfile? {
        return runCatching { userInfoEndpoint.profile().toUserProfile() }.getOrElse { null }
    }
}
