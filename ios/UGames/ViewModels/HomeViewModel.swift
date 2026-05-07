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
    @Published private(set) var continueRow: [Game] = []
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

    /// Picks Hero / Spotlight / per-genre rows from the editorial blocks.
    /// Hero falls back to the highest-rated flat game so the page never
    /// renders without one when the feed misses an `l`-sized block.
    private func digest(blocks: [FeedBlock], flat: [Game]) {
        let heroBlock = blocks.first(where: { $0.type == "categorized" && $0.size == "l" })
        hero = heroBlock?.items.first ?? flat.max(by: { $0.ratingCount < $1.ratingCount })
        let spotlightBlock = blocks.first(where: {
            $0.type == "categorized" && $0.size == "s" && $0.items.count >= 5
        })
        spotlight = spotlightBlock.map { SpotlightBlock(title: $0.title, games: $0.items) }
        let rows = blocks
            .filter { $0.type == "categorized" }
            .filter { spotlightBlock == nil || $0.title != spotlightBlock!.title }
            .prefix(8)
            .map { b -> GenreRow in
                let items = (heroBlock != nil && b.title == heroBlock!.title)
                    ? Array(b.items.dropFirst())
                    : b.items
                return GenreRow(title: b.title, games: items)
            }
            .filter { !$0.games.isEmpty }
        genreRows = Array(rows)
    }
}
