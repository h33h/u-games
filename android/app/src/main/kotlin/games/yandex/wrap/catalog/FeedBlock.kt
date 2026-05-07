package games.yandex.wrap.catalog

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
 * Result of [CatalogApi.firstFeedPageWithBlocks]: blocks (Home editorial),
 * deduped flat list (Browse), and the server-side `recentGames` top-level
 * array. [genres] stays empty here — Yandex's JSON response doesn't include
 * navigation categories on mobile platforms, so [CatalogApi.fetchCategories]
 * scrapes them from the SSR HTML separately.
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
 * One category tab parsed from the SSR `__appData__.categoriesForTabs`.
 * [name] is the slug used as the `tab=` query param on `/feed/`; [title]
 * is the localized label shown on chips.
 */
data class GameCategory(
    val name: String,
    val title: String,
    val gamesCount: Int,
)
