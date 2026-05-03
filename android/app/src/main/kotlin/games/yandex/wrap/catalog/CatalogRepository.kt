package games.yandex.wrap.catalog

import games.yandex.wrap.data.FavoritesDao
import games.yandex.wrap.data.GameCacheDao
import games.yandex.wrap.data.GameCacheEntity
import games.yandex.wrap.data.FavoriteEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

class CatalogRepository(
    private val api: CatalogApi,
    private val cache: GameCacheDao,
    private val favorites: FavoritesDao,
) {

    fun feed(): Flow<Result<List<Game>>> = flow {
        val cached = cache.latest(50).map { it.toGame() }
        if (cached.isNotEmpty()) emit(Result.success(cached))
        try {
            val fresh = api.feed()
            cache.upsertAll(fresh.map { it.toEntity() })
            emit(Result.success(fresh))
        } catch (t: Throwable) {
            if (cached.isEmpty()) emit(Result.failure(t))
        }
    }

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
