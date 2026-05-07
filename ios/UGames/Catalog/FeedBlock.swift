import Foundation

/// One block from the `feed` array in `/api/catalogue/v2/feed/`.
/// Yandex returns the catalog as a list of editorial blocks rather than a
/// flat grid: each block has a `type` (`categorized` / `suggested` / `promo`),
/// an optional `size` (`l` / `s`), a localized `title` and a list of items.
/// Home uses the block structure to drive Hero / Spotlight / per-genre rows;
/// Browse keeps using the flattened list.
struct FeedBlock: Equatable {
    let type: String
    let size: String?
    let title: String
    let items: [Game]
}

/// Result of `CatalogService.fetchFeedWithBlocks` — both the editorial
/// blocks (Home) and the deduped flat list (Browse / cache). `genres` is
/// harvested from `siteNavigationLinks.categories` so Browse chips don't
/// need a separate request.
struct FeedWithBlocks: Equatable {
    let blocks: [FeedBlock]
    let flatGames: [Game]
    let genres: [String]
    let nextPageId: String?
    let hasNext: Bool
}
