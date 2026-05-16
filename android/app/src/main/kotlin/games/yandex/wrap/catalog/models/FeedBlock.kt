package games.yandex.wrap.catalog.models

/**
 * One block from the `feed` array in `/api/catalogue/v2/feed/`.
 *
 * Yandex returns the catalog as a list of editorial blocks rather than a
 * flat grid: each block has a [type] (`categorized` / `suggested` / `promo`),
 * an optional [size] (`l` / `s`), a localized [title] and a list of items.
 * Home uses the block structure to drive Hero / Spotlight / per-genre rows;
 * Browse keeps using the flattened list.
 */
data class FeedBlock(
    val type: String,
    val size: String?,
    val title: String,
    val items: List<Game>,
)

/**
 * Result of the first feed page with blocks: blocks (Home editorial),
 * deduped flat list (Browse), and the server-side `recentGames` top-level
 * array. [genres] stays empty here; navigation chips come from `/tags/`.
 */
data class FeedWithBlocks(
    val blocks: List<FeedBlock>,
    val flatGames: List<Game>,
    val recentGames: List<Game>,
    val genres: List<String>,
    val nextPageId: String?,
    val hasNext: Boolean,
)

/**
 * One category/tag chip parsed from `/games/api/catalogue/v2/tags/`.
 */
data class GameCategory(
    val name: String,
    val title: String,
    val gamesCount: Int,
)
