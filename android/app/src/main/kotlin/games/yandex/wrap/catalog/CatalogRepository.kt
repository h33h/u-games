package games.yandex.wrap.catalog

import games.yandex.wrap.data.FavoritesDao
import games.yandex.wrap.data.GameCacheDao
import games.yandex.wrap.data.GameCacheEntity
import games.yandex.wrap.data.FavoriteEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

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

    suspend fun userProfile(): UserProfile = api.userProfile()

    /// Resilient profile fetch: poll CookieManager for `Session_id` on the
    /// locale-preferred Yandex domain (≤3s), then retry the SSR fetch with
    /// growing back-off so the avatar/Plus pill eventually reflects the
    /// authenticated session even if the WebView's cookie flush is still
    /// in flight after AuthScreen closes. Mirrors the original logic from
    /// CatalogViewModel.refreshProfile (now removed) so Home + Profile both
    /// behave the same way.
    suspend fun userProfileWithRetry(attempts: Int = 4): UserProfile {
        val cm = android.webkit.CookieManager.getInstance()
        val preferredHost =
            if (java.util.Locale.getDefault().language.lowercase().startsWith("ru")) "yandex.ru" else "yandex.com"
        val deadline = System.currentTimeMillis() + 3000
        while (System.currentTimeMillis() < deadline) {
            val raw = cm.getCookie("https://$preferredHost").orEmpty()
            if (raw.contains("Session_id=")) break
            kotlinx.coroutines.delay(150)
        }
        val delaysMs = longArrayOf(0, 350, 800, 1600)
        var last: UserProfile = UserProfile(false, "", "", "", false)
        for (i in 0 until attempts) {
            val d = delaysMs[i.coerceAtMost(delaysMs.size - 1)]
            if (d > 0) kotlinx.coroutines.delay(d)
            val p = runCatching { api.userProfile() }.getOrNull() ?: continue
            last = p
            if (p.isAuthorized) return p
        }
        return last
    }

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
