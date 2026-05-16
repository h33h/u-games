package games.yandex.wrap.catalog

import games.yandex.wrap.data.FavoriteEntity
import games.yandex.wrap.data.FavoritesDao
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class FavoritesRepository(
    private val favorites: FavoritesDao,
) {
    fun favoritesAsGames(): Flow<List<Game>> = favorites.observeAll().map { list ->
        list.map { it.toGame() }
    }

    fun favoriteIds(): Flow<Set<Long>> = favorites.observeAll().map { list ->
        list.map { it.appId }.toSet()
    }

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
                ),
            )
        }
    }
}

private fun FavoriteEntity.toGame(): Game = Game(
    appId = appId,
    title = title,
    rating = 0f,
    ratingCount = 0,
    coverUrl = coverUrl,
    iconUrl = coverUrl,
    categories = emptyList(),
    developer = "",
)
