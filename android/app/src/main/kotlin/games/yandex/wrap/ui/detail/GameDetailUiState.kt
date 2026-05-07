package games.yandex.wrap.ui.detail

import games.yandex.wrap.catalog.Game

/**
 * State for the GameDetail push screen. The `game` is the seed passed in
 * by the caller (we don't have a fetch-by-id endpoint and don't need one;
 * every callsite already has a full `Game` object on hand).
 *
 * Phase 3: the only async piece is the "More like this" row, which calls
 * `similar_games`. Favorites are observed off the repository so the heart
 * icon stays in sync with what the rest of the app sees.
 */
data class GameDetailUiState(
    val game: Game,
    val isFavorite: Boolean = false,
    val favoriteIds: Set<Long> = emptySet(),
    val similar: List<Game> = emptyList(),
    val isLoadingSimilar: Boolean = false,
    val similarError: String? = null,
)
