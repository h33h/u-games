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

/// Result of `CatalogService.fetchFeedWithBlocks` — editorial blocks (Home),
/// the deduped flat list (Browse / cache), and the server-side recents
/// list which lives at the response root (not inside `feed[]`). `genres`
/// is unused in the JSON response and stays empty here — Browse loads
/// categories separately via `CatalogService.fetchCategories()`.
struct FeedWithBlocks: Equatable {
    let blocks: [FeedBlock]
    let flatGames: [Game]
    let recentGames: [Game]
    let genres: [String]
    let nextPageId: String?
    let hasNext: Bool
}

/// A category tab parsed from the SSR `__appData__.categoriesForTabs`.
/// `name` is the slug used as the `tab=` query param when calling
/// `/api/catalogue/v2/feed/?tab=<name>`. `title` is the localized label,
/// `gamesCount` is the badge number on the chip.
struct GameCategory: Equatable, Identifiable {
    let name: String
    let title: String
    let gamesCount: Int
    var id: String { name }
}
