package games.yandex.wrap.catalog

import games.yandex.wrap.data.FavoritesDao
import games.yandex.wrap.data.GameCacheDao
import games.yandex.wrap.data.GameCacheEntity
import games.yandex.wrap.data.FavoriteEntity
import games.yandex.wrap.data.RecentGameEntity
import games.yandex.wrap.data.RecentGamesDao
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class CatalogRepository(
    private val api: CatalogApi,
    private val cache: GameCacheDao,
    private val favorites: FavoritesDao,
    private val recents: RecentGamesDao,
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

    /// Drops every Yandex cookie from the WebView's CookieManager so the next
    /// request to /games/ is anonymous. The Ktor HTTP client reads cookies
    /// directly from CookieManager via AndroidWebViewCookieStorage, so a single
    /// flush is enough to log the user out from both sides.
    suspend fun clearSession() {
        val cm = android.webkit.CookieManager.getInstance()
        // CookieManager has no enumerate API, so we wipe yandex domains by
        // re-setting each cookie with Max-Age=0 on the known hosts.
        val hosts = listOf(
            "https://yandex.com",
            "https://yandex.ru",
            "https://passport.yandex.com",
            "https://passport.yandex.ru",
            "https://games.yandex.com",
            "https://games.yandex.ru",
            "https://id.yandex.com",
        )
        for (host in hosts) {
            val raw = cm.getCookie(host) ?: continue
            for (pair in raw.split(';')) {
                val name = pair.substringBefore('=').trim()
                if (name.isEmpty()) continue
                cm.setCookie(host, "$name=; Max-Age=0; Path=/")
            }
        }
        cm.flush()
    }

    fun favoritesAsGames(): Flow<List<Game>> = favorites.observeAll().map { list ->
        list.map { it.toGame() }
    }

    fun favoriteIds(): Flow<Set<Long>> = favorites.observeAll().map { list ->
        list.map { it.appId }.toSet()
    }

    fun recentGames(limit: Int = 20): Flow<List<Game>> =
        recents.observe(limit).map { list -> list.map { it.toGame() } }

    suspend fun recordOpen(game: Game) {
        recents.insert(
            RecentGameEntity(
                appId = game.appId,
                title = game.title,
                rating = game.rating,
                ratingCount = game.ratingCount,
                coverUrl = game.coverUrl,
                iconUrl = game.iconUrl,
                openedAtMs = System.currentTimeMillis(),
            )
        )
        recents.trim()
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

private fun RecentGameEntity.toGame(): Game = Game(
    appId = appId,
    title = title,
    rating = rating,
    ratingCount = ratingCount,
    coverUrl = coverUrl,
    iconUrl = iconUrl,
    categories = emptyList(),
    developer = "",
)

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
