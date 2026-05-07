import Foundation
import Combine

struct SpotlightBlock: Equatable {
    let title: String
    let games: [Game]
}

struct GenreRow: Equatable {
    let title: String
    let categoryName: String?
    let games: [Game]
}

/// Backs `HomeView`. Loads:
/// 1. main feed → hero + spotlight + a "fresh today" suggested row,
/// 2. server-side `recentGames` → Continue row (overrides local recents),
/// 3. top N categories from SSR + per-category feed → genre rows.
///
/// Yandex's JSON feed only ever returns 1–4 untitled `suggested` blocks for
/// mobile platforms, so the only way to get distinct, titled rows on Home
/// is to fan out one feed call per top category. We do that in parallel
/// once and cache the result for the session.
@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?
    @Published private(set) var hero: Game?
    /// Local recents (RecentGamesStore). Fallback for the Continue row when
    /// the server-side `recentGames` is empty (anonymous user).
    @Published private(set) var continueRow: [Game] = []
    /// Server-side `recentGames` from the authenticated feed. Overrides
    /// `continueRow` for the Continue row label.
    @Published private(set) var feedRecent: [Game] = []
    @Published private(set) var favoritesRow: [Game] = []
    @Published private(set) var spotlight: SpotlightBlock?
    @Published private(set) var genreRows: [GenreRow] = []
    @Published private(set) var profile: UserProfile = .anonymous

    private let service: CatalogService
    private let recents: RecentGamesStore
    private let favorites: FavoritesStore
    private var cancellables = Set<AnyCancellable>()
    private var loaded = false

    /// How many category rows to fan out on Home. Each row costs one feed
    /// fetch, so 6 keeps cold start under a second on a fast network.
    private let categoryRowLimit = 6

    init(service: CatalogService, recents: RecentGamesStore, favorites: FavoritesStore) {
        self.service = service
        self.recents = recents
        self.favorites = favorites
        recents.$games
            .receive(on: RunLoop.main)
            .sink { [weak self] g in self?.continueRow = Array(g.prefix(12)) }
            .store(in: &cancellables)
        favorites.$games
            .receive(on: RunLoop.main)
            .sink { [weak self] g in self?.favoritesRow = Array(g.prefix(12)) }
            .store(in: &cancellables)
        service.$profile
            .receive(on: RunLoop.main)
            .sink { [weak self] p in self?.profile = p }
            .store(in: &cancellables)
    }

    func loadInitialIfNeeded() async {
        if loaded { return }
        loaded = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            // Main feed first — fast path for hero / spotlight / recents.
            let main = try await service.fetchFeedWithBlocks()
            digest(main: main)
            // Then categories + per-category fan-out (parallel). This is what
            // populates the visible "rows" on Home — the bare /feed/ JSON
            // never carries titled categorized blocks on mobile platforms.
            let categories = (try? await service.fetchCategories()) ?? []
            await fanOutGenreRows(categories: categories, exclude: main.flatGames.first?.appId)
        } catch {
            self.error = error.localizedDescription
        }
        await service.refreshProfile()
    }

    func toggleFavorite(_ game: Game) {
        favorites.toggle(game)
    }

    /// Hero comes from the first item of the first non-promo block, or the
    /// highest-rated flat game as a last resort. Spotlight is the first
    /// block with ≥5 items that isn't already supplying the hero. The
    /// "Fresh today" row picks up the rest of the first block (minus hero)
    /// as a quick-win row before the per-category rows finish loading.
    private func digest(main: FeedWithBlocks) {
        func isPromo(_ b: FeedBlock) -> Bool {
            b.type.compare("promo", options: .caseInsensitive) == .orderedSame
                || b.type.compare("adv", options: .caseInsensitive) == .orderedSame
        }
        let heroBlock = main.blocks.first(where: { !isPromo($0) && !$0.items.isEmpty })
        hero = heroBlock?.items.first ?? main.flatGames.max(by: { $0.ratingCount < $1.ratingCount })

        let spotlightBlock = main.blocks.first(where: {
            !isPromo($0) && $0 != heroBlock && $0.items.count >= 5
        })
        spotlight = spotlightBlock.map {
            SpotlightBlock(title: $0.title.isEmpty ? "Featured" : $0.title, games: $0.items)
        }

        // Server-side recent games override local recents.
        feedRecent = Array(main.recentGames.prefix(12))

        // First row before per-category fan-out: the rest of the hero block.
        if let hb = heroBlock, hb.items.count > 1 {
            let rest = Array(hb.items.dropFirst())
            genreRows = [GenreRow(title: "Fresh today", categoryName: nil, games: rest)]
        } else {
            genreRows = []
        }
    }

    /// Fans out one feed call per top category and renders each as a
    /// genre row. Updates `genreRows` incrementally so the user sees rows
    /// land as they arrive.
    private func fanOutGenreRows(categories: [GameCategory], exclude heroAppId: Int64?) async {
        let pick = Array(categories.prefix(categoryRowLimit))
        guard !pick.isEmpty else { return }

        let initial = genreRows
        var rows: [String: GenreRow] = [:]

        await withTaskGroup(of: (String, GenreRow?).self) { group in
            for cat in pick {
                group.addTask { [weak self] in
                    guard let self = self else { return (cat.name, nil) }
                    let resp = try? await self.service.fetchFeedWithBlocks(tab: cat.name)
                    let items = (resp?.flatGames ?? []).filter { $0.appId != heroAppId }
                    if items.isEmpty { return (cat.name, nil) }
                    return (cat.name, GenreRow(title: cat.title, categoryName: cat.name, games: Array(items.prefix(15))))
                }
            }
            for await (name, row) in group {
                if let row = row { rows[name] = row }
            }
        }

        // Preserve the order of `pick` — task groups deliver completions
        // out of order.
        let ordered = pick.compactMap { rows[$0.name] }
        genreRows = initial + ordered
    }
}
