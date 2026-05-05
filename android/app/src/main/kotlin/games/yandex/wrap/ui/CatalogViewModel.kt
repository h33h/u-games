package games.yandex.wrap.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.catalog.UserProfile
import games.yandex.wrap.diagnostics.LogStore
import java.util.Locale
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class CatalogViewModel(private val repository: CatalogRepository) : ViewModel() {

    private val pageSize = 24

    private val _state = MutableStateFlow(CatalogUiState())
    val state: StateFlow<CatalogUiState> = _state.asStateFlow()

    val recent: StateFlow<List<Game>> = repository.recentGames()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    val favorites: StateFlow<List<Game>> = repository.favoritesAsGames()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    val favoriteIds: StateFlow<Set<Long>> = repository.favoriteIds()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptySet())

    private var searchDebounceJob: Job? = null

    init {
        viewModelScope.launch {
            val cached = repository.cachedFeed()
            if (cached.isNotEmpty()) {
                _state.update { it.copy(games = cached) }
            }
            refreshFeed()
            refreshProfile()
        }
    }

    fun refreshFeed() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null, mode = Mode.Feed) }
            val result = runCatching { repository.firstFeedPage(pageSize) }
            _state.update { current ->
                result.fold(
                    onSuccess = { page ->
                        current.copy(
                            games = page.games,
                            isLoading = false,
                            isLoadingMore = false,
                            hasMore = page.hasNext && page.nextPageId != null,
                            nextPageId = page.nextPageId,
                            error = null,
                            mode = Mode.Feed,
                        )
                    },
                    onFailure = { err ->
                        current.copy(
                            isLoading = false,
                            error = if (current.games.isEmpty()) err.message else null,
                        )
                    }
                )
            }
        }
    }

    fun loadMore() {
        val current = _state.value
        if (current.mode != Mode.Feed) return
        if (current.isLoading || current.isLoadingMore || !current.hasMore) return
        val pageId = current.nextPageId ?: return

        _state.update { it.copy(isLoadingMore = true) }
        viewModelScope.launch {
            val result = runCatching { repository.nextFeedPage(pageId, pageSize) }
            _state.update { state ->
                result.fold(
                    onSuccess = { page ->
                        val merged = (state.games + page.games).distinctBy { it.appId }
                        state.copy(
                            games = merged,
                            isLoadingMore = false,
                            hasMore = page.hasNext && page.nextPageId != null,
                            nextPageId = page.nextPageId,
                            error = null,
                        )
                    },
                    onFailure = { err ->
                        state.copy(isLoadingMore = false, error = err.message)
                    }
                )
            }
        }
    }

    fun onSearchChange(query: String) {
        _state.update { it.copy(searchQuery = query) }
        searchDebounceJob?.cancel()
        if (query.isBlank()) {
            refreshFeed()
            return
        }
        searchDebounceJob = viewModelScope.launch {
            delay(400)
            performSearch(query)
        }
    }

    fun submitSearch() {
        searchDebounceJob?.cancel()
        val q = _state.value.searchQuery
        if (q.isBlank()) refreshFeed() else viewModelScope.launch { performSearch(q) }
    }

    /// Re-fetch the profile up to [attempts] times with growing back-off.
    /// Reason: just after the auth WebView redirects to /games/, the new
    /// Session_id cookie has only just landed in WebView's CookieManager.
    /// AndroidWebViewCookieStorage reads it on demand, but the WebView's own
    /// flush is asynchronous, so an immediate fetch may still see the
    /// anonymous session. We first poll CookieManager for Session_id (max 3s)
    /// so the retry loop starts from a known-good state, then retry on top
    /// of that to absorb residual SSR/edge propagation latency.
    fun refreshProfile(attempts: Int = 4) {
        viewModelScope.launch {
            LogStore.log("profile", "refreshProfile begin")
            val waited = waitForSessionCookie(timeoutMs = 3000)
            LogStore.log("profile", "Session_id wait: $waited")
            val delaysMs = longArrayOf(0, 350, 800, 1600)
            for (i in 0 until attempts) {
                val d = delaysMs[i.coerceAtMost(delaysMs.size - 1)]
                if (d > 0) delay(d)
                val profile = runCatching { repository.userProfile() }.getOrNull()
                LogStore.log(
                    "profile",
                    "attempt#${i + 1} -> isAuth=${profile?.isAuthorized} login=${profile?.login.orEmpty()}",
                )
                if (profile != null && profile.isAuthorized) {
                    _state.update { it.copy(profile = profile) }
                    return@launch
                }
                if (i == attempts - 1 && profile != null) {
                    _state.update { it.copy(profile = profile) }
                }
            }
            LogStore.log("profile", "refreshProfile end (still anonymous)")
        }
    }

    /**
     * Wait for Session_id on the locale-preferred Yandex domain. Russian
     * users authenticate against passport.yandex.ru and CookieManager will
     * only return cookies scoped to that host; polling yandex.com would
     * never see the session and time out incorrectly.
     */
    private suspend fun waitForSessionCookie(timeoutMs: Long): String {
        val cm = android.webkit.CookieManager.getInstance()
        val preferredHost = if (Locale.getDefault().language.lowercase().startsWith("ru")) "yandex.ru" else "yandex.com"
        val deadline = System.currentTimeMillis() + timeoutMs
        var ticks = 0
        while (System.currentTimeMillis() < deadline) {
            val raw = cm.getCookie("https://$preferredHost").orEmpty()
            if (raw.contains("Session_id=")) {
                return "found@$preferredHost after ${ticks * 150}ms"
            }
            delay(150)
            ticks++
        }
        return "TIMEOUT@$preferredHost after ${timeoutMs}ms"
    }

    fun signOut() {
        viewModelScope.launch {
            runCatching { repository.clearSession() }
            _state.update { it.copy(profile = UserProfile(false, "", "", "", false)) }
        }
    }

    fun recordGameOpen(game: Game) {
        viewModelScope.launch {
            runCatching { repository.recordOpen(game) }
        }
    }

    fun toggleFavorite(game: Game) {
        viewModelScope.launch {
            runCatching { repository.toggleFavorite(game) }
        }
    }

    private suspend fun performSearch(query: String) {
        _state.update { it.copy(isLoading = true, error = null, mode = Mode.Search) }
        val result = runCatching { repository.search(query) }
        _state.update { state ->
            result.fold(
                onSuccess = { hits ->
                    state.copy(
                        games = hits,
                        isLoading = false,
                        isLoadingMore = false,
                        hasMore = false,
                        nextPageId = null,
                        error = null,
                        mode = Mode.Search,
                    )
                },
                onFailure = { err ->
                    state.copy(isLoading = false, error = err.message)
                }
            )
        }
    }
}

enum class Mode { Feed, Search }

data class CatalogUiState(
    val games: List<Game> = emptyList(),
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val hasMore: Boolean = false,
    val nextPageId: String? = null,
    val error: String? = null,
    val searchQuery: String = "",
    val mode: Mode = Mode.Feed,
    val profile: UserProfile = UserProfile(false, "", "", "", false),
)
