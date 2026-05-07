package games.yandex.wrap.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.FeedBlock
import games.yandex.wrap.catalog.Game
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Backs HomeScreen. Loads the editorial feed once on init, derives hero /
 * spotlight / per-genre rows by [digest], and live-merges Continue (recents)
 * and Favorites rows from local stores so they update without a refetch.
 *
 * Profile is fetched best-effort — Home shows the avatar but Profile-tab
 * owns the full profile lifecycle.
 */
class HomeViewModel(private val repository: CatalogRepository) : ViewModel() {

    private val _state = MutableStateFlow(HomeUiState())
    val state: StateFlow<HomeUiState> = _state.asStateFlow()

    val recent: StateFlow<List<Game>> = repository.recentGames()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    val favorites: StateFlow<List<Game>> = repository.favoritesAsGames()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    init {
        refresh()
        viewModelScope.launch {
            combine(recent, favorites) { r, f -> r to f }.collect { (r, f) ->
                _state.update { it.copy(continueRow = r.take(12), favoritesRow = f.take(12)) }
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            val result = runCatching { repository.firstFeedWithBlocks() }
            result.fold(
                onSuccess = { feed ->
                    val (hero, spotlight, genreRows) = digest(feed.blocks, feed.flatGames)
                    _state.update {
                        it.copy(
                            isLoading = false,
                            error = null,
                            hero = hero,
                            spotlight = spotlight,
                            genreRows = genreRows,
                        )
                    }
                },
                onFailure = { err ->
                    _state.update { it.copy(isLoading = false, error = err.message) }
                },
            )
            refreshProfile()
        }
    }

    fun toggleFavorite(game: Game) {
        viewModelScope.launch { runCatching { repository.toggleFavorite(game) } }
    }

    private fun refreshProfile() {
        viewModelScope.launch {
            val p = runCatching { repository.userProfile() }.getOrNull()
            if (p != null) _state.update { it.copy(profile = p) }
        }
    }

    /// Picks Hero / Spotlight / per-genre rows from the editorial blocks.
    /// Hero falls back to the highest-rated flat game so the page never
    /// renders without one when the feed misses an `l`-sized block.
    private fun digest(
        blocks: List<FeedBlock>,
        flat: List<Game>,
    ): Triple<Game?, SpotlightBlock?, List<GenreRow>> {
        val heroBlock = blocks.firstOrNull { it.type == "categorized" && it.size == "l" }
        val hero = heroBlock?.items?.firstOrNull() ?: flat.maxByOrNull { it.ratingCount }
        val spotlightBlock = blocks.firstOrNull {
            it.type == "categorized" && it.size == "s" && it.items.size >= 5
        }
        val spotlight = spotlightBlock?.let { SpotlightBlock(it.title, it.items) }
        val genreRows = blocks
            .filter { it.type == "categorized" && it !== spotlightBlock }
            .take(8)
            .map { b ->
                val items = if (b === heroBlock) b.items.drop(1) else b.items
                GenreRow(b.title, items)
            }
            .filter { it.games.isNotEmpty() }
        return Triple(hero, spotlight, genreRows)
    }
}
