package games.yandex.wrap.catalog

import games.yandex.wrap.data.FavoritesDao
import games.yandex.wrap.data.GameCacheDao
import games.yandex.wrap.data.GameCacheEntity
import games.yandex.wrap.data.FavoriteEntity
import kotlinx.coroutines.flow.Flow

class CatalogRepository(
    private val api: CatalogApi,
    private val cache: GameCacheDao,
    private val favorites: FavoritesDao,
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

    suspend fun cachedFeed(limit: Int = 50): List<Game> =
        cache.latest(limit).map { it.toGame() }

    suspend fun search(query: String): List<Game> = api.search(query = query)

    suspend fun similar(appId: Long): Result<List<Game>> = runCatching {
        api.similar(appId)
    }

    suspend fun userProfile(): UserProfile = api.userProfile()

    fun favorites(): Flow<List<FavoriteEntity>> = favorites.observeAll()

    suspend fun isFavorite(appId: Long): Boolean = favorites.isFavorite(appId)

    suspend fun toggleFavorite(game: Game) {
        if (favorites.isFavorite(game.appId)) {
            favorites.delete(game.appId)
        } else {
            favorites.insert(
                FavoriteEntity(
                    appId = game.appId,
                    title = game.title,
                    coverUrl = game.coverUrl,
                    addedAtMs = System.currentTimeMillis(),
                )
            )
        }
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
