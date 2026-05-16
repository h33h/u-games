package games.yandex.wrap.ui.browse

import games.yandex.wrap.catalog.models.Game
import games.yandex.wrap.catalog.models.GameCategory

/**
 * View-state for BrowseScreen. Genre filter is server-side via the
 * `?tab=<name>` query param so paging is consistent with the chip choice.
 * Search uses the paginated REST endpoint, so [hasMore] is honoured in
 * both feed and search modes.
 */
data class BrowseUiState(
    val mode: BrowseMode = BrowseMode.Feed,
    val games: List<Game> = emptyList(),
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val hasMore: Boolean = false,
    val nextPageId: String? = null,
    val error: String? = null,
    val searchQuery: String = "",
    val categories: List<GameCategory> = emptyList(),
    val selectedCategory: GameCategory? = null,
)

enum class BrowseMode { Feed, Search }
