package games.yandex.wrap.ui.home

import games.yandex.wrap.catalog.Game
import games.yandex.wrap.catalog.UserProfile

/**
 * View-state for HomeScreen. Built by [HomeViewModel.digest] from the
 * editorial feed plus local stores (recents / favorites). Hero is null
 * before the first response — the UI renders a Skeleton in that case.
 */
data class HomeUiState(
    val isLoading: Boolean = false,
    val error: String? = null,
    val hero: Game? = null,
    /// Server-side `recentGames` from the authenticated feed. Drives the
    /// "My games" row on Home. Yandex tracks recents per profile so we
    /// no longer maintain a local fallback list.
    val feedRecent: List<Game> = emptyList(),
    val favoritesRow: List<Game> = emptyList(),
    val spotlight: SpotlightBlock? = null,
    val genreRows: List<GenreRow> = emptyList(),
    val profile: UserProfile? = null,
)
