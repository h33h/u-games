import Foundation

@MainActor
final class BrowseViewModel: ObservableObject {
    enum Mode { case feed, search }

    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var error: String?
    @Published var searchQuery: String = "" { didSet { onQueryChanged(searchQuery) } }
    @Published private(set) var categories: [GameCategory] = []
    @Published var selectedCategory: GameCategory? = nil
    @Published private(set) var mode: Mode = .feed

    @Published private(set) var searchFocusRequest: Int = 0

    private let service: CatalogService
    private var nextPageId: String?
    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var loaded = false

    init(service: CatalogService) {
        self.service = service
    }

    var visibleGames: [Game] { games }

    func loadInitialIfNeeded() async {
        if loaded { return }
        loaded = true
        await refresh()
    }

    func refresh() async {
        searchTask?.cancel()
        loadTask?.cancel()
        mode = .feed
        isLoading = true
        error = nil
        defer { isLoading = false }

        if categories.isEmpty {
            categories = (try? await service.fetchCategories()) ?? []
        }
        do {
            let feed = try await service.fetchFeedWithBlocks(tab: selectedCategory?.name)
            games = feed.flatGames
            hasMore = feed.hasNext && feed.nextPageId != nil
            nextPageId = feed.nextPageId
        } catch {
            if games.isEmpty { self.error = error.localizedDescription }
        }
    }

    func loadMore() {
        guard hasMore, !isLoading, !isLoadingMore, let pageId = nextPageId else { return }
        let modeSnapshot = mode
        let querySnapshot = searchQuery
        let knownSnapshot = Set(games.map { $0.appId })
        isLoadingMore = true
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            defer { Task { @MainActor in self.isLoadingMore = false } }
            do {
                let page: CatalogService.FeedPage
                if modeSnapshot == .search {
                    page = try await self.service.fetchSearchPaginated(query: querySnapshot, pageId: pageId)
                } else {
                    page = try await self.service.fetchFeed(pageId: pageId)
                }
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

    func submitSearch() {
        searchTask?.cancel()
        let q = searchQuery
        if q.isEmpty {
            Task { await refresh() }
        } else {
            Task { await performSearch(q) }
        }
    }

    func setCategory(_ c: GameCategory?) {
        selectedCategory = c
        Task { await refresh() }
    }

    func setCategoryByName(_ raw: String) {
        Task {
            if categories.isEmpty {
                categories = (try? await service.fetchCategories()) ?? []
            }
            let match = categories.first(where: { $0.name == raw })
                ?? categories.first(where: { $0.title.localizedCaseInsensitiveCompare(raw) == .orderedSame })
            await MainActor.run {
                selectedCategory = match
            }
            await refresh()
        }
    }

    func requestSearchFocus() {
        searchFocusRequest &+= 1
    }

    private func onQueryChanged(_ q: String) {
        searchTask?.cancel()
        if q.isEmpty {
            Task { await refresh() }
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await self?.performSearch(q)
        }
    }

    private func performSearch(_ q: String) async {
        mode = .search
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let page = try await service.fetchSearchPaginated(query: q, pageId: nil)
            games = page.games
            hasMore = page.hasNext && page.nextPageId != nil
            nextPageId = page.nextPageId
        } catch {
            self.error = error.localizedDescription
        }
    }
}
