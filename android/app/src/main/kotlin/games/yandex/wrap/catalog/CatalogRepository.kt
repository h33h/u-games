package games.yandex.wrap.catalog

import games.yandex.wrap.catalog.models.AppDetail
import games.yandex.wrap.catalog.models.FeedPage
import games.yandex.wrap.catalog.models.FeedWithBlocks
import games.yandex.wrap.catalog.models.Game
import games.yandex.wrap.catalog.models.GameCategory
import games.yandex.wrap.data.GameCacheDao
import games.yandex.wrap.data.GameCacheEntity

class CatalogRepository(
    private val api: CatalogApi,
    private val cache: GameCacheDao,
) {

    suspend fun firstFeedPage(gamesPerPage: Int = 24): FeedPage {
        val page = api.firstFeedPage(gamesPerPage = gamesPerPage)
        if (page.games.isNotEmpty()) {
            cache.upsertAll(page.games.map { it.toEntity() })
        }
        return page
    }

    suspend fun nextFeedPage(pageId: String, gamesPerPage: Int = 24): FeedPage =
        api.nextFeedPage(pageId, gamesPerPage)

    /**
     * Block-aware first page for Home. Caches the deduped flat list so the
     * Browse cold-start (which calls [cachedFeed]) stays warm even when the
     * user lands on Home first.
     */
    suspend fun firstFeedWithBlocks(gamesPerPage: Int = 24, tab: String? = null): FeedWithBlocks {
        val resp = api.firstFeedPageWithBlocks(gamesPerPage = gamesPerPage, tab = tab)
        if (resp.flatGames.isNotEmpty()) {
            cache.upsertAll(resp.flatGames.map { it.toEntity() })
        }
        return resp
    }

    suspend fun searchPaginated(query: String, pageId: String? = null): FeedPage =
        api.searchPaginated(query = query, pageId = pageId)

    suspend fun categories(): List<GameCategory> = api.fetchCategories()

    suspend fun cachedFeed(limit: Int = 50): List<Game> =
        cache.latest(limit).map { it.toGame() }

    suspend fun search(query: String): List<Game> = api.search(query = query)

    suspend fun similar(appId: Long): Result<List<Game>> = runCatching {
        api.similar(appId)
    }

    suspend fun appDetail(appId: Long): Result<AppDetail?> = runCatching {
        api.appDetail(appId)
    }
}

private fun Game.toEntity(): GameCacheEntity = GameCacheEntity(
    appId = appId,
    title = title,
    rating = rating,
    ratingCount = ratingCount,
    coverUrl = coverUrl,
    iconUrl = iconUrl,
    categories = categories,
    developer = developer,
    updatedAtMs = System.currentTimeMillis(),
)

private fun GameCacheEntity.toGame(): Game = Game(
    appId = appId,
    title = title,
    rating = rating,
    ratingCount = ratingCount,
    coverUrl = coverUrl,
    iconUrl = iconUrl,
    categories = categories,
    developer = developer,
)
