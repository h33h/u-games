import Foundation
import Combine

@MainActor
final class CatalogService: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var error: String?
    @Published var searchQuery: String = "" {
        didSet { onQueryChanged(searchQuery) }
    }

    private(set) var mode: Mode = .feed
    private var loadedSkip: Int = 0
    private let pageSize: Int = 24

    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    enum Mode { case feed, search }

    private let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    func loadInitial() async {
        if !games.isEmpty { return }
        await refreshFeed()
    }

    func refreshFeed() async {
        searchTask?.cancel()
        loadTask?.cancel()
        mode = .feed
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fresh = try await fetchFeed(skip: 0)
            games = fresh
            hasMore = fresh.count >= pageSize
            loadedSkip = fresh.count
        } catch {
            if games.isEmpty { self.error = error.localizedDescription }
        }
    }

    func loadMore() {
        guard mode == .feed, hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            defer { Task { @MainActor in self.isLoadingMore = false } }
            do {
                let more = try await self.fetchFeed(skip: self.loadedSkip)
                let known = Set(self.games.map { $0.appId })
                let dedup = more.filter { !known.contains($0.appId) }
                await MainActor.run {
                    self.games.append(contentsOf: dedup)
                    self.hasMore = more.count >= self.pageSize
                    self.loadedSkip = self.games.count
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
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

    func submitSearch() {
        searchTask?.cancel()
        let q = searchQuery
        if q.isEmpty {
            Task { await refreshFeed() }
        } else {
            Task { await performSearch(q) }
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
            loadedSkip = 0
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchFeed(skip: Int, gamesPerPage: Int = 24, lang: String = "en") async throws -> [Game] {
        var components = URLComponents(string: "https://yandex.com/games/api/catalogue/v2/feed/")!
        var items = [
            URLQueryItem(name: "with_promos", value: "true"),
            URLQueryItem(name: "lang", value: lang),
            URLQueryItem(name: "games_count", value: String(gamesPerPage)),
            URLQueryItem(name: "categorized_size", value: "5"),
            URLQueryItem(name: "with_recent_games", value: "true"),
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "client_width", value: "390"),
            URLQueryItem(name: "client_height", value: "844"),
        ]
        if skip > 0,
           let pageId = "gamesSkip=\(skip)".data(using: .utf8)?.base64EncodedString() {
            items.append(URLQueryItem(name: "page_id", value: pageId))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [[String: Any]] else { return [] }
        return GameDecoder.flatten(feed)
    }

    private func fetchSearch(query: String, lang: String = "en") async throws -> [Game] {
        var components = URLComponents(string: "https://yandex.com/games/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "lang", value: lang),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        guard let json = extractAppData(html) else { return [] }
        guard let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let search = parsed["search"] as? [String: Any],
              let blocks = search["data"] as? [[String: Any]] else { return [] }
        return GameDecoder.flatten(blocks)
    }

    private func extractAppData(_ html: String) -> String? {
        guard let markerRange = html.range(of: "id=\"__appData__\"") else { return nil }
        guard let openIdx = html.range(of: ">", range: markerRange.upperBound..<html.endIndex) else { return nil }
        guard let closeIdx = html.range(of: "</script>", range: openIdx.upperBound..<html.endIndex) else { return nil }
        return String(html[openIdx.upperBound..<closeIdx.lowerBound])
    }
}

private enum GameDecoder {
    static func flatten(_ blocks: [[String: Any]]) -> [Game] {
        var seen = Set<Int64>()
        var out: [Game] = []
        for block in blocks {
            guard let items = block["items"] as? [[String: Any]] else { continue }
            for item in items {
                guard let game = parse(item) else { continue }
                if seen.insert(game.appId).inserted { out.append(game) }
            }
        }
        return out
    }

    private static func parse(_ item: [String: Any]) -> Game? {
        guard let appId = (item["appID"] as? NSNumber)?.int64Value,
              let title = item["title"] as? String else { return nil }
        let rating = (item["rating"] as? NSNumber)?.doubleValue ?? 0
        let ratingCount = (item["ratingCount"] as? NSNumber)?.intValue ?? 0
        let media = item["media"] as? [String: Any]
        let cover = (media?["cover"] as? [String: Any])?["prefix-url"] as? String
        let icon = (media?["icon"] as? [String: Any])?["prefix-url"] as? String
        let categories = (item["categoriesNames"] as? [String]) ?? []
        let developer = (item["developer"] as? [String: Any])?["name"] as? String ?? ""
        let coverUrl = cover.map { "\($0)pjpg250x140" } ?? ""
        let iconUrl = (icon ?? cover).map { "\($0)pjpg256x256" } ?? ""
        return Game(
            appId: appId,
            title: title,
            rating: rating,
            ratingCount: ratingCount,
            coverUrl: coverUrl,
            iconUrl: iconUrl,
            categories: categories,
            developer: developer
        )
    }
}
