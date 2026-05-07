import Foundation
import Combine

struct SpotlightBlock: Equatable {
    let title: String
    let games: [Game]
}

struct GenreRow: Equatable {
    let title: String
    let games: [Game]
}

/// Backs `HomeView`. Loads the editorial feed once on init, derives
/// hero / spotlight / per-genre rows from the editorial blocks, and
/// live-merges Continue (recents) and Favorites rows from the local
/// stores so they update without a refetch.
@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?
    @Published private(set) var hero: Game?
    /// Local recents (RecentGamesStore). Fallback for the Continue row when
    /// the authenticated feed didn't return a server-side recent block.
    @Published private(set) var continueRow: [Game] = []
    /// Server-side "recently_played" block from the authenticated feed.
    /// Takes precedence over `continueRow` for the Continue row.
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
            let feed = try await service.fetchFeedWithBlocks()
            digest(blocks: feed.blocks, flat: feed.flatGames)
        } catch {
            self.error = error.localizedDescription
        }
        await service.refreshProfile()
    }

    func toggleFavorite(_ game: Game) {
        favorites.toggle(game)
    }

    /// Picks Hero / Spotlight / per-genre rows + server-side recents from
    /// the editorial blocks. Hero falls back to the highest-rated flat game
    /// so the page never renders without one. Genre rows include any non-
    /// promo, non-recent block with a non-empty title and ≥3 items so the
    /// layout stays full even when the feed only marks one block
    /// `categorized`.
    private func digest(blocks: [FeedBlock], flat: [Game]) {
        func isRecent(_ b: FeedBlock) -> Bool {
            b.type.range(of: "recent", options: .caseInsensitive) != nil
        }
        func isPromo(_ b: FeedBlock) -> Bool {
            b.type.compare("promo", options: .caseInsensitive) == .orderedSame
        }

        let recentBlock = blocks.first(where: isRecent)
        let heroBlock = blocks.first(where: { !isRecent($0) && !isPromo($0) && $0.size == "l" })
            ?? blocks.first(where: { !isRecent($0) && !isPromo($0) && !$0.items.isEmpty })
        hero = heroBlock?.items.first ?? flat.max(by: { $0.ratingCount < $1.ratingCount })

        let spotlightBlock = blocks.first(where: {
            !isRecent($0) && !isPromo($0)
                && $0.title != heroBlock?.title
                && $0.size == "s" && $0.items.count >= 5 && !$0.title.isEmpty
        })
        spotlight = spotlightBlock.map { SpotlightBlock(title: $0.title, games: $0.items) }

        let excludedTitles = Set([heroBlock?.title, spotlightBlock?.title, recentBlock?.title].compactMap { $0 })
        let rows = blocks
            .filter { !isRecent($0) && !isPromo($0) }
            .filter { !excludedTitles.contains($0.title) }
            .filter { !$0.title.isEmpty && $0.items.count >= 3 }
            .prefix(8)
            .map { GenreRow(title: $0.title, games: $0.items) }
        genreRows = Array(rows)
        feedRecent = Array((recentBlock?.items ?? []).prefix(12))
    }
}
