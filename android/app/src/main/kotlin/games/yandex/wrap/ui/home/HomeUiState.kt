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
    /// Locally tracked recents (from RecentGamesStore). Used as a fallback
    /// when the authenticated feed didn't return a server-side recent block.
    val localRecent: List<Game> = emptyList(),
    /// Server-side "recently_played" block from the authenticated feed.
    /// Takes precedence over [localRecent] for the Continue row.
    val feedRecent: List<Game> = emptyList(),
    val favoritesRow: List<Game> = emptyList(),
    val spotlight: SpotlightBlock? = null,
    val genreRows: List<GenreRow> = emptyList(),
    val profile: UserProfile = UserProfile(false, "", "", "", false),
)

data class SpotlightBlock(val title: String, val games: List<Game>)
data class GenreRow(val title: String, val games: List<Game>)
