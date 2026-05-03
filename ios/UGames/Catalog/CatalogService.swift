import Foundation
import Combine

struct UserProfile: Equatable {
    var isAuthorized: Bool
    var displayName: String
    var login: String
    var avatarUrl: String
    var hasYaPlus: Bool

    static let anonymous = UserProfile(isAuthorized: false, displayName: "", login: "", avatarUrl: "", hasYaPlus: false)
}

@MainActor
final class CatalogService: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var error: String?
    @Published private(set) var profile: UserProfile = .anonymous
    @Published var searchQuery: String = "" {
        didSet { onQueryChanged(searchQuery) }
    }

    private(set) var mode: Mode = .feed
    private var nextPageId: String?
    private let pageSize: Int = 24

    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    enum Mode { case feed, search }

    private let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

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

    /// Re-fetch the profile up to `attempts` times with growing back-off.
    /// Reason: just after the auth WebView redirects to `/games/`, the new
    /// `Session_id` cookie has only just landed in WKWebView's cookie store.
    /// `SharedCookieStore` mirrors it to `URLSession.shared` asynchronously,
    /// so an immediate fetch may still see the anonymous session and report
    /// `isAuthorized=false`. Retrying gives the cookie bridge time to catch up.
    func refreshProfile(attempts: Int = 4) async {
        let delaysMs: [UInt64] = [0, 350, 800, 1600]
        for i in 0..<attempts {
            if delaysMs[min(i, delaysMs.count - 1)] > 0 {
                try? await Task.sleep(nanoseconds: delaysMs[min(i, delaysMs.count - 1)] * 1_000_000)
            }
            if let p = try? await fetchProfile(), p.isAuthorized {
                profile = p
                return
            }
            // Last attempt: even if anonymous, commit it so the UI reflects the
            // actual state (e.g. user signed out elsewhere).
            if i == attempts - 1, let p = try? await fetchProfile() {
                profile = p
            }
        }
    }

    func clearSession() async {
        let store = HTTPCookieStorage.shared
        for cookie in store.cookies ?? [] {
            if cookie.domain.contains("yandex") {
                store.deleteCookie(cookie)
            }
        }
        // Clear WKWebView cookies too via SharedCookieStore observer side.
        await SharedCookieStore.shared.clearYandexCookies()
        profile = .anonymous
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

    private struct FeedPage {
        let games: [Game]
        let nextPageId: String?
        let hasNext: Bool
    }

    private func fetchFeed(pageId: String?, gamesPerPage: Int = 24, lang: String = "en") async throws -> FeedPage {
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
        if let pageId = pageId {
            items.append(URLQueryItem(name: "page_id", value: pageId))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [[String: Any]] else { return FeedPage(games: [], nextPageId: nil, hasNext: false) }
        let games = GameDecoder.flatten(feed)
        let pageInfo = root["pageInfo"] as? [String: Any]
        let next = pageInfo?["nextPageId"] as? String
        let hasNext = (pageInfo?["hasNextPage"] as? Bool) ?? (next != nil)
        return FeedPage(games: games, nextPageId: next, hasNext: hasNext)
    }

    /// Fetch games similar to the given app from Yandex's recommender. Used
    /// by the (future) game-detail row "More like this". Returns [] on any
    /// failure — caller decides whether to show the row.
    func fetchSimilar(appId: Int64, lang: String = "en") async -> [Game] {
        var components = URLComponents(string: "https://yandex.com/games/api/catalogue/v2/similar_games/")!
        components.queryItems = [
            URLQueryItem(name: "app_id", value: String(appId)),
            URLQueryItem(name: "games_count", value: "16"),
            URLQueryItem(name: "int", value: "true"),
            URLQueryItem(name: "lang", value: lang),
            URLQueryItem(name: "page_type", value: "game"),
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "standalone", value: "false"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let feed = root["feed"] as? [[String: Any]] else { return [] }
            return GameDecoder.flatten(feed)
        } catch {
            return []
        }
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

    private func fetchProfile(lang: String = "en") async throws -> UserProfile {
        var components = URLComponents(string: "https://yandex.com/games/")!
        components.queryItems = [URLQueryItem(name: "lang", value: lang)]
        var request = URLRequest(url: components.url!)
        request.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { return .anonymous }
        guard let json = extractAppData(html) else { return .anonymous }
        guard let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let userData = parsed["userData"] as? [String: Any] else { return .anonymous }
        let uid = (userData["uid"] as? String) ?? ""
        guard !uid.isEmpty else { return .anonymous }
        let avatarsOrigin = (userData["avatarsOrigin"] as? String) ?? "https://avatars.mds.yandex.net"
        let avatarId = (userData["avatarId"] as? String) ?? "0/0-0"
        let avatarUrl = avatarId == "0/0-0" ? "" : "\(avatarsOrigin)/get-yapic/\(avatarId)/islands-300"
        return UserProfile(
            isAuthorized: true,
            displayName: (userData["displayName"] as? String) ?? "",
            login: (userData["login"] as? String) ?? "",
            avatarUrl: avatarUrl,
            hasYaPlus: (userData["yaplusEnabled"] as? Bool) ?? false
        )
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
