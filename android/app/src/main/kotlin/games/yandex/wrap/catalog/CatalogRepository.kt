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

    suspend fun feedPage(skip: Int, gamesPerPage: Int = 24): List<Game> {
        val games = api.feed(skip = skip, gamesPerPage = gamesPerPage)
        if (skip == 0 && games.isNotEmpty()) {
            cache.upsertAll(games.map { it.toEntity() })
        }
        return games
    }

    suspend fun cachedFeed(limit: Int = 50): List<Game> =
        cache.latest(limit).map { it.toGame() }

    suspend fun search(query: String): List<Game> = api.search(query = query)

    suspend fun similar(appId: Long): Result<List<Game>> = runCatching {
        api.similar(appId)
    }

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
