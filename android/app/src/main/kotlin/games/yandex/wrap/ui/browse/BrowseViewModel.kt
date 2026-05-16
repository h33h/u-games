package games.yandex.wrap.ui.browse

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.FavoritesRepository
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.catalog.GameCategory
import games.yandex.wrap.util.appendUniqueBy
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
 * Backs BrowseScreen — feed pagination + server-side category filter via
 * `?tab=<name>` + paginated REST search. Categories load once per session
 * from the SSR catalog HTML.
 */
class BrowseViewModel(
    private val catalogRepository: CatalogRepository,
    private val favoritesRepository: FavoritesRepository,
) : ViewModel() {

    private val pageSize = 24

    private val _state = MutableStateFlow(BrowseUiState())
    val state: StateFlow<BrowseUiState> = _state.asStateFlow()

    val favoriteIds: StateFlow<Set<Long>> = favoritesRepository.favoriteIds()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptySet())

    private val _searchFocusRequest = MutableStateFlow(0L)
    val searchFocusRequest: StateFlow<Long> = _searchFocusRequest.asStateFlow()

    private var searchDebounceJob: Job? = null

    init {
        viewModelScope.launch {
            val cached = catalogRepository.cachedFeed()
            if (cached.isNotEmpty()) _state.update { it.copy(games = cached) }
            ensureCategories()
            refresh()
        }
    }

    fun refresh() {
        viewModelScope.launch {
            val tab = _state.value.selectedCategory?.name
            _state.update { it.copy(isLoading = true, error = null, mode = BrowseMode.Feed) }
            ensureCategories()
            val result = runCatching { catalogRepository.firstFeedWithBlocks(gamesPerPage = pageSize, tab = tab) }
            _state.update { current ->
                result.fold(
                    onSuccess = { feed ->
                        current.copy(
                            games = feed.flatGames,
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
        if (current.isLoading || current.isLoadingMore || !current.hasMore) return
        val pageId = current.nextPageId ?: return
        val mode = current.mode
        val query = current.searchQuery
        _state.update { it.copy(isLoadingMore = true) }
        viewModelScope.launch {
            val result = runCatching {
                if (mode == BrowseMode.Search) catalogRepository.searchPaginated(query, pageId)
                else catalogRepository.nextFeedPage(pageId, pageSize)
            }
            _state.update { state ->
                result.fold(
                    onSuccess = { page ->
                        state.copy(
                            games = state.games.appendUniqueBy(page.games) { it.appId },
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

    fun setCategory(category: GameCategory?) {
        _state.update { it.copy(selectedCategory = category) }
        refresh()
    }

    /// Resolve a raw name OR localized title against the loaded categories
    /// — used by HomeView's "See all" handler that only knows row.title /
    /// row.categoryName.
    fun setCategoryByName(raw: String) {
        viewModelScope.launch {
            ensureCategories()
            val cats = _state.value.categories
            val match = cats.firstOrNull { it.name == raw }
                ?: cats.firstOrNull { it.title.equals(raw, ignoreCase = true) }
            _state.update { it.copy(selectedCategory = match) }
            refresh()
        }
    }

    fun toggleFavorite(game: Game) {
        viewModelScope.launch { runCatching { favoritesRepository.toggleFavorite(game) } }
    }

    fun requestSearchFocus() {
        _searchFocusRequest.value = System.currentTimeMillis()
    }

    private suspend fun ensureCategories() {
        if (_state.value.categories.isNotEmpty()) return
        val cats = runCatching { catalogRepository.categories() }.getOrNull().orEmpty()
        if (cats.isNotEmpty()) _state.update { it.copy(categories = cats) }
    }

    private suspend fun performSearch(query: String) {
        _state.update { it.copy(isLoading = true, error = null, mode = BrowseMode.Search) }
        val result = runCatching { catalogRepository.searchPaginated(query) }
        _state.update { state ->
            result.fold(
                onSuccess = { page ->
                    state.copy(
                        games = page.games,
                        isLoading = false,
                        isLoadingMore = false,
                        hasMore = page.hasNext && page.nextPageId != null,
                        nextPageId = page.nextPageId,
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
