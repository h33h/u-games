import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?
    @Published private(set) var hero: Game?

    @Published private(set) var feedRecent: [Game] = []
    @Published private(set) var favoritesRow: [Game] = []
    @Published private(set) var spotlight: SpotlightBlock?
    @Published private(set) var genreRows: [GenreRow] = []
    @Published private(set) var profile: UserProfile?

    private let service: CatalogService
    private let favorites: FavoritesStore
    private var cancellables = Set<AnyCancellable>()
    private var loaded = false

    private let categoryRowLimit = 6

    init(service: CatalogService, favorites: FavoritesStore) {
        self.service = service
        self.favorites = favorites
        favorites.$games
            .receive(on: RunLoop.main)
            .sink { [weak self] g in self?.favoritesRow = Array(g.prefix(12)) }
            .store(in: &cancellables)
        service.$profile
            .receive(on: RunLoop.main)
            .sink { [weak self] p in
                guard let self = self else { return }
                let wasAnon = self.profile?.isAuthorized != true
                self.profile = p

                if wasAnon && p?.isAuthorized == true && self.loaded {
                    Task { await self.refreshFeedOnly() }
                }
            }
            .store(in: &cancellables)

        service.$gameSessionEndCount
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, self.loaded else { return }
                Task { await self.refreshFeedOnly() }
            }
            .store(in: &cancellables)
    }

    private func refreshFeedOnly() async {
        do {
            let main = try await service.fetchFeedWithBlocks()
            digest(main: main)
            let categories = (try? await service.fetchCategories()) ?? []
            await fanOutGenreRows(categories: categories, exclude: main.flatGames.first?.appId)
        } catch {
            self.error = error.localizedDescription
        }
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
            let main = try await service.fetchFeedWithBlocks()
            digest(main: main)

            let categories = (try? await service.fetchCategories()) ?? []
            await fanOutGenreRows(categories: categories, exclude: main.flatGames.first?.appId)
        } catch {
            self.error = error.localizedDescription
        }

        let svc = service
        Task.detached(priority: .userInitiated) {
            await svc.refreshProfile()
        }
    }

    func toggleFavorite(_ game: Game) {
        favorites.toggle(game)
    }

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

        feedRecent = Array(main.recentGames.prefix(12))

        if let hb = heroBlock, hb.items.count > 1 {
            let rest = Array(hb.items.dropFirst())
            genreRows = [GenreRow(title: "Fresh today", categoryName: nil, games: rest)]
        } else {
            genreRows = []
        }
    }

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

        let ordered = pick.compactMap { rows[$0.name] }
        genreRows = initial + ordered
    }
}
