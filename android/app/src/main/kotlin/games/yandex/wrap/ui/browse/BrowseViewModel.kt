package games.yandex.wrap.ui.browse

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.Game
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Backs BrowseScreen — feed pagination + client-side genre filter + search.
 *
 * Hooks into the same [CatalogRepository] as Home so cached covers stay
 * warm. The first `firstFeedWithBlocks` call doubles as the source of the
 * genre vocabulary; subsequent pages use the legacy flat pagination.
 */
class BrowseViewModel(private val repository: CatalogRepository) : ViewModel() {

    private val pageSize = 24

    private val _state = MutableStateFlow(BrowseUiState())
    val state: StateFlow<BrowseUiState> = _state.asStateFlow()

    val favoriteIds: StateFlow<Set<Long>> = repository.favoriteIds()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptySet())

    private var searchDebounceJob: Job? = null

    init {
        viewModelScope.launch {
            val cached = repository.cachedFeed()
            if (cached.isNotEmpty()) _state.update { it.copy(games = cached) }
            refresh()
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null, mode = BrowseMode.Feed) }
            val result = runCatching { repository.firstFeedWithBlocks(gamesPerPage = pageSize) }
            _state.update { current ->
                result.fold(
                    onSuccess = { feed ->
                        current.copy(
                            games = feed.flatGames,
                            genres = feed.genres,
                            isLoading = false,
                            isLoadingMore = false,
                            hasMore = feed.hasNext && feed.nextPageId != null,
                            nextPageId = feed.nextPageId,
                            error = null,
                            mode = BrowseMode.Feed,
                        )
                    },
                    onFailure = { err ->
                        current.copy(
                            isLoading = false,
                            error = if (current.games.isEmpty()) err.message else null,
                        )
                    },
                )
            }
        }
    }

    fun loadMore() {
        val current = _state.value
        if (current.mode != BrowseMode.Feed) return
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
                    },
                )
            }
        }
    }

    fun onSearchChange(query: String) {
        _state.update { it.copy(searchQuery = query) }
        searchDebounceJob?.cancel()
        if (query.isBlank()) {
            refresh()
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
        if (q.isBlank()) refresh() else viewModelScope.launch { performSearch(q) }
    }

    fun setGenre(genre: String?) {
        _state.update { it.copy(selectedGenre = genre) }
    }

    fun toggleFavorite(game: Game) {
        viewModelScope.launch { runCatching { repository.toggleFavorite(game) } }
    }

    /// Client-side filter applied at render time. The grid asks for
    /// `visibleGames(state)` instead of `state.games` so chip switching
    /// stays instant — paginated network fetches still cover *all* games
    /// under the hood, the chip just narrows the view.
    fun visibleGames(state: BrowseUiState): List<Game> {
        if (state.mode == BrowseMode.Search) return state.games
        val sel = state.selectedGenre ?: return state.games
        return state.games.filter { g ->
            g.categories.any { it.equals(sel, ignoreCase = true) }
        }
    }

    private suspend fun performSearch(query: String) {
        _state.update { it.copy(isLoading = true, error = null, mode = BrowseMode.Search) }
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
                        mode = BrowseMode.Search,
                    )
                },
                onFailure = { err ->
                    state.copy(isLoading = false, error = err.message)
                },
            )
        }
    }
}
