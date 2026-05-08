import Foundation

@MainActor
final class CategoryGamesViewModel: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var error: String?

    let categoryName: String
    let displayTitle: String

    private let service: CatalogService
    private var nextPageId: String?
    private var loadTask: Task<Void, Never>?
    private var loaded = false

    init(service: CatalogService, categoryName: String, displayTitle: String) {
        self.service = service
        self.categoryName = categoryName
        self.displayTitle = displayTitle
    }

    func loadInitialIfNeeded() async {
        if loaded { return }
        loaded = true
        await refresh()
    }

    func refresh() async {
        loadTask?.cancel()
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let feed = try await service.fetchFeedWithBlocks(tab: categoryName)
            games = feed.flatGames
            hasMore = feed.hasNext && feed.nextPageId != nil
            nextPageId = feed.nextPageId
        } catch {
            if games.isEmpty { self.error = error.localizedDescription }
        }
    }

    func loadMore() {
        guard hasMore, !isLoading, !isLoadingMore, let pageId = nextPageId else { return }
        let knownSnapshot = Set(games.map { $0.appId })
        isLoadingMore = true
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            defer { Task { @MainActor in self.isLoadingMore = false } }
            do {
                let page = try await self.service.fetchFeed(pageId: pageId)
                let dedup = page.games.filter { !knownSnapshot.contains($0.appId) }
                await MainActor.run {
                    self.games.append(contentsOf: dedup)
                    self.hasMore = page.hasNext && page.nextPageId != nil
                    self.nextPageId = page.nextPageId
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
    }
}
