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
 * Result of [CatalogApi.firstFeedPageWithBlocks]: both the raw blocks (for
 * Home's editorial layout) and the deduped flat list (for Browse / cache).
 * [genres] is harvested from the feed's `siteNavigationLinks.categories`
 * so Browse chips don't need a separate request.
 */
data class FeedWithBlocks(
    val blocks: List<FeedBlock>,
    val flatGames: List<Game>,
    val genres: List<String>,
    val nextPageId: String?,
    val hasNext: Boolean,
)
