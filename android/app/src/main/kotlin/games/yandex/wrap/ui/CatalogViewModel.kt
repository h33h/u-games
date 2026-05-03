package games.yandex.wrap.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.catalog.UserProfile
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

    fun refreshProfile() {
        viewModelScope.launch {
            val profile = runCatching { repository.userProfile() }.getOrDefault(UserProfile(false, "", "", "", false))
            _state.update { it.copy(profile = profile) }
        }
    }

    fun recordGameOpen(game: Game) {
        viewModelScope.launch {
            runCatching { repository.recordOpen(game) }
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
