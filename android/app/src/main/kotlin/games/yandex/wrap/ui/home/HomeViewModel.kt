package games.yandex.wrap.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.FeedBlock
import games.yandex.wrap.catalog.FeedWithBlocks
import games.yandex.wrap.catalog.GameCategory
import games.yandex.wrap.catalog.Game
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Backs HomeScreen. Loads:
 * 1. main feed → hero + spotlight + a "fresh today" suggested row,
 * 2. server-side `recentGames` → Continue row (overrides local recents),
 * 3. top N categories from SSR + per-category feed → genre rows.
 *
 * Yandex's JSON feed only ever returns 1–4 untitled `suggested` blocks for
 * mobile platforms, so the only way to get distinct, titled rows on Home
 * is to fan out one feed call per top category. Done in parallel once and
 * cached for the session.
 */
class HomeViewModel(private val repository: CatalogRepository) : ViewModel() {

    private val _state = MutableStateFlow(HomeUiState())
    val state: StateFlow<HomeUiState> = _state.asStateFlow()

    val recent: StateFlow<List<Game>> = repository.recentGames()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    val favorites: StateFlow<List<Game>> = repository.favoritesAsGames()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    private val categoryRowLimit = 6

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
            val mainResult = runCatching { repository.firstFeedWithBlocks() }
            mainResult.fold(
                onSuccess = { feed ->
                    val (hero, spotlight, freshRow) = digestMain(feed)
                    _state.update {
                        it.copy(
                            isLoading = false,
                            error = null,
                            hero = hero,
                            spotlight = spotlight,
                            feedRecent = feed.recentGames.take(12),
                            // Initial rows = "Fresh today" only; per-category rows
                            // arrive incrementally as fan-out finishes.
                            genreRows = listOfNotNull(freshRow),
                        )
                    }
                    fanOutGenreRows(excludeAppId = hero?.appId, prefix = listOfNotNull(freshRow))
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

    /// Picks Hero + Spotlight + a "Fresh today" row from the main feed.
    /// Genre rows come from `fanOutGenreRows` because mobile-platform feeds
    /// don't carry titled `categorized` blocks.
    private fun digestMain(feed: FeedWithBlocks): Triple<Game?, SpotlightBlock?, GenreRow?> {
        fun isPromo(b: FeedBlock) =
            b.type.equals("promo", ignoreCase = true) || b.type.equals("adv", ignoreCase = true)
        val heroBlock = feed.blocks.firstOrNull { !isPromo(it) && it.items.isNotEmpty() }
        val hero = heroBlock?.items?.firstOrNull() ?: feed.flatGames.maxByOrNull { it.ratingCount }
        val spotlightBlock = feed.blocks.firstOrNull {
            !isPromo(it) && it !== heroBlock && it.items.size >= 5
        }
        val spotlight = spotlightBlock?.let {
            SpotlightBlock(it.title.ifEmpty { "Featured" }, it.items)
        }
        val freshRow = heroBlock?.items?.drop(1)?.takeIf { it.isNotEmpty() }?.let {
            GenreRow(title = "Fresh today", categoryName = null, games = it)
        }
        return Triple(hero, spotlight, freshRow)
    }

    /// Fans out one feed call per top category and merges results into
    /// `genreRows`. Done in parallel; results are reordered to match the
    /// original category list before being published.
    private suspend fun fanOutGenreRows(excludeAppId: Long?, prefix: List<GenreRow>) {
        val categories = runCatching { repository.categories() }.getOrNull().orEmpty()
        if (categories.isEmpty()) return
        val pick = categories.take(categoryRowLimit)
        val rows: List<Pair<GameCategory, List<Game>>> = coroutineScope {
            pick.map { cat ->
                async {
                    val feed = runCatching { repository.firstFeedWithBlocks(tab = cat.name) }.getOrNull()
                    val items = (feed?.flatGames.orEmpty()).filter { it.appId != excludeAppId }
                    cat to items.take(15)
                }
            }.awaitAll()
        }
        val ordered = rows
            .filter { it.second.isNotEmpty() }
            .map { (cat, items) -> GenreRow(title = cat.title, categoryName = cat.name, games = items) }
        _state.update { it.copy(genreRows = prefix + ordered) }
    }
}
