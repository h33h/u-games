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
                _state.update { it.copy(localRecent = r.take(12), favoritesRow = f.take(12)) }
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            val result = runCatching { repository.firstFeedWithBlocks() }
            result.fold(
                onSuccess = { feed ->
                    val digested = digest(feed.blocks, feed.flatGames)
                    _state.update {
                        it.copy(
                            isLoading = false,
                            error = null,
                            hero = digested.hero,
                            feedRecent = digested.feedRecent,
                            spotlight = digested.spotlight,
                            genreRows = digested.genreRows,
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
            val p = runCatching { repository.userProfileWithRetry() }.getOrNull()
            if (p != null) _state.update { it.copy(profile = p) }
        }
    }

    private data class Digest(
        val hero: Game?,
        val feedRecent: List<Game>,
        val spotlight: SpotlightBlock?,
        val genreRows: List<GenreRow>,
    )

    /// Picks Hero / Spotlight / per-genre rows + server-side recents from the
    /// editorial blocks. Hero falls back to the highest-rated flat game so
    /// the page never renders without one. Genre rows include any non-promo,
    /// non-recent block with a non-empty title and ≥3 items so the layout
    /// stays full even when the feed only marks one block `categorized`.
    private fun digest(blocks: List<FeedBlock>, flat: List<Game>): Digest {
        fun isRecent(b: FeedBlock) = b.type.contains("recent", ignoreCase = true)
        fun isPromo(b: FeedBlock) = b.type.equals("promo", ignoreCase = true)

        val recentBlock = blocks.firstOrNull(::isRecent)
        val heroBlock = blocks.firstOrNull {
            !isRecent(it) && !isPromo(it) && it.size == "l"
        } ?: blocks.firstOrNull { !isRecent(it) && !isPromo(it) && it.items.isNotEmpty() }
        val hero = heroBlock?.items?.firstOrNull() ?: flat.maxByOrNull { it.ratingCount }

        val spotlightBlock = blocks.firstOrNull {
            !isRecent(it) && !isPromo(it) && it !== heroBlock
                && it.size == "s" && it.items.size >= 5 && it.title.isNotEmpty()
        }
        val spotlight = spotlightBlock?.let { SpotlightBlock(it.title, it.items) }

        val excluded = setOfNotNull(heroBlock, spotlightBlock, recentBlock)
        val genreRows = blocks
            .asSequence()
            .filter { !isRecent(it) && !isPromo(it) && it !in excluded }
            .filter { it.title.isNotEmpty() && it.items.size >= 3 }
            .take(8)
            .map { GenreRow(it.title, it.items) }
            .toList()

        return Digest(
            hero = hero,
            feedRecent = recentBlock?.items.orEmpty().take(12),
            spotlight = spotlight,
            genreRows = genreRows,
        )
    }
}
