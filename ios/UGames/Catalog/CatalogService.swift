import Foundation
import Combine

@MainActor
final class CatalogService: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var error: String?
    @Published private(set) var profile: UserProfile?

    @Published private(set) var gameSessionEndCount: Int = 0

    @Published var searchQuery: String = "" {
        didSet { onQueryChanged(searchQuery) }
    }

    private(set) var mode: Mode = .feed
    private var nextPageId: String?
    private let pageSize: Int = 24

    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    private let remote: YandexCatalogRemoteDataSource
    private let sessionStore: YandexSessionStore

    enum Mode { case feed, search }

    init(environment: AppEnvironment) {
        self.remote = environment.remote
        self.sessionStore = environment.sessionStore
    }

    func notifyGameSessionEnded() { gameSessionEndCount &+= 1 }

    func loadInitial() async {
        if !games.isEmpty { return }
        await refreshFeed()
        await refreshProfile()
    }

    func refreshFeed() async {
        searchTask?.cancel()
        loadTask?.cancel()
        mode = .feed
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let page = try await fetchFeed(pageId: nil)
            games = page.games
            hasMore = page.hasNext && page.nextPageId != nil
            nextPageId = page.nextPageId
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
                let page = try await self.fetchFeed(pageId: pageId)
                await MainActor.run {
                    self.games.appendUnique(contentsOf: page.games) { $0.appId }
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
            Task { await refreshFeed() }
        } else {
            Task { await performSearch(q) }
        }
    }

    func refreshProfile(attempts: Int = 4) async {
        Log.write("profile", "refreshProfile begin")
        await SharedCookieStore.shared.syncToShared()
        Log.write("profile", "WK->shared sync done")
        let cookie = await sessionStore.sessionCookieHeader(timeoutSeconds: 3.0)
        Log.write("profile", "Session_id wait: cookies=\(cookie.count) names=\(cookie.names)")
        let delaysMs: [UInt64] = [0, 350, 800, 1600]
        for i in 0..<attempts {
            if delaysMs[min(i, delaysMs.count - 1)] > 0 {
                try? await Task.sleep(nanoseconds: delaysMs[min(i, delaysMs.count - 1)] * 1_000_000)
            }
            do {
                let cookie = await sessionStore.sessionCookieHeader(timeoutSeconds: 0)
                Log.write("profile", "fetch begin cookies=\(cookie.count)[\(cookie.names)]")
                let (p, status, hops, html) = try await remote.fetchProfile(cookieHeader: cookie.header)
                Log.write("profile", "fetch http status=\(status) bodyLen=\(html.count) hops=\(hops)")
                Log.write("profile", "attempt#\(i + 1) -> isAuth=\(p?.isAuthorized ?? false) login=\(p?.login ?? "") uid-len=\(p?.displayName.count ?? 0)")
                if let p, p.isAuthorized {
                    profile = p
                    return
                }
                if i == attempts - 1 { profile = p }
            } catch {
                Log.write("profile", "attempt#\(i + 1) FAILED: \(error.localizedDescription)")
            }
        }
        Log.write("profile", "refreshProfile end (no authorized profile)")
    }

    func clearSession() async {
        await sessionStore.clearSession()
        profile = nil
    }

    func fetchFeedWithBlocks(
        gamesPerPage: Int = 24,
        lang: String = "en",
        tab: String? = nil
    ) async throws -> FeedWithBlocks {
        try await remote.fetchFeedWithBlocks(gamesPerPage: gamesPerPage, lang: lang, tab: tab)
    }

    func fetchSearchPaginated(
        query: String,
        pageId: String? = nil,
        gamesPerPage: Int = 24,
        lang: String = "en"
    ) async throws -> FeedPage {
        try await remote.fetchSearchPaginated(query: query, pageId: pageId, gamesPerPage: gamesPerPage, lang: lang)
    }

    func fetchCategories(lang: String = "en") async throws -> [GameCategory] {
        try await remote.fetchCategories(lang: lang)
    }

    func fetchFeed(pageId: String?, gamesPerPage: Int = 24, lang: String = "en") async throws -> FeedPage {
        try await remote.fetchFeed(pageId: pageId, gamesPerPage: gamesPerPage, lang: lang)
    }

    func fetchAppDetail(appId: Int64, lang: String = "en") async -> AppDetail? {
        await remote.fetchAppDetail(appId: appId, lang: lang)
    }

    func fetchSimilar(appId: Int64, lang: String = "en") async -> [Game] {
        await remote.fetchSimilar(appId: appId, lang: lang)
    }

    func fetchSearch(query: String, lang: String = "en") async throws -> [Game] {
        try await remote.fetchSearch(query: query, lang: lang)
    }

    private func onQueryChanged(_ q: String) {
        searchTask?.cancel()
        if q.isEmpty {
            Task { await refreshFeed() }
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await self?.performSearch(q)
        }
    }

    private func performSearch(_ query: String) async {
        mode = .search
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            games = try await fetchSearch(query: query)
            hasMore = false
            nextPageId = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
