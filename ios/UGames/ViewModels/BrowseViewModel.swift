import Foundation

/// Backs `BrowseView` — feed pagination + client-side genre filter +
/// search. Mirrors `BrowseViewModel.kt` on Android: chip switching is
/// instant (visibleGames filters on the loaded list), pagination feeds
/// more pages into `games` under the hood.
@MainActor
final class BrowseViewModel: ObservableObject {
    enum Mode { case feed, search }

    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var error: String?
    @Published var searchQuery: String = "" { didSet { onQueryChanged(searchQuery) } }
    @Published private(set) var genres: [String] = []
    @Published var selectedGenre: String? = nil
    @Published private(set) var mode: Mode = .feed

    private let service: CatalogService
    private var nextPageId: String?
    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var loaded = false

    init(service: CatalogService) {
        self.service = service
    }

    /// Filters `games` by `selectedGenre` so chip flips don't await the
    /// network. The full `games` list keeps growing as pagination runs;
    /// the chip only narrows what's visible.
    var visibleGames: [Game] {
        guard mode == .feed, let g = selectedGenre, !g.isEmpty else { return games }
        return games.filter { $0.categories.contains { $0.localizedCaseInsensitiveCompare(g) == .orderedSame } }
    }

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
        do {
            let feed = try await service.fetchFeedWithBlocks()
            games = feed.flatGames
            genres = feed.genres
            hasMore = feed.hasNext && feed.nextPageId != nil
            nextPageId = feed.nextPageId
        } catch {
            if games.isEmpty { self.error = error.localizedDescription }
        }
    }

    func loadMore() {
        guard mode == .feed, hasMore, !isLoading, !isLoadingMore, let pageId = nextPageId else { return }
        isLoadingMore = true
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            defer { Task { @MainActor in self.isLoadingMore = false } }
            do {
                let page = try await self.service.fetchFeed(pageId: pageId)
                let known = Set(self.games.map { $0.appId })
                let dedup = page.games.filter { !known.contains($0.appId) }
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

    func setGenre(_ g: String?) {
        selectedGenre = g
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
            let hits = try await service.fetchSearch(query: q)
            games = hits
            hasMore = false
            nextPageId = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
