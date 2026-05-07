package games.yandex.wrap.ui.browse

import games.yandex.wrap.catalog.Game

/**
 * View-state for BrowseScreen. Genre filter is client-side: the chip rebuilds
 * the visible list from the loaded `games` (see [BrowseViewModel.visibleGames])
 * so switching chips never blocks on a network round-trip. Pagination is
 * driven by [nextPageId] which is only set when [mode] == [BrowseMode.Feed].
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
    val genres: List<String> = emptyList(),
    val selectedGenre: String? = null,
)

enum class BrowseMode { Feed, Search }
