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
    /// `isAuthorized=false`. Force one synchronous WK→shared sync, poll the
    /// shared store for `Session_id` (max 3s), then retry to absorb residual
    /// SSR/edge propagation latency.
    func refreshProfile(attempts: Int = 4) async {
        Log.write("profile", "refreshProfile begin")
        await SharedCookieStore.shared.syncToShared()
        Log.write("profile", "WK->shared sync done")
        let waited = await Self.waitForSessionCookie(timeoutSeconds: 3.0)
        Log.write("profile", "Session_id wait: \(waited)")
        let delaysMs: [UInt64] = [0, 350, 800, 1600]
        for i in 0..<attempts {
            if delaysMs[min(i, delaysMs.count - 1)] > 0 {
                try? await Task.sleep(nanoseconds: delaysMs[min(i, delaysMs.count - 1)] * 1_000_000)
            }
            do {
                let p = try await fetchProfile()
                Log.write("profile", "attempt#\(i+1) -> isAuth=\(p.isAuthorized) login=\(p.login) uid-len=\(p.displayName.count)")
                if p.isAuthorized {
                    profile = p
                    return
                }
                if i == attempts - 1 { profile = p }
            } catch {
                Log.write("profile", "attempt#\(i+1) FAILED: \(error.localizedDescription)")
            }
        }
        Log.write("profile", "refreshProfile end (still anonymous)")
    }

    private static func waitForSessionCookie(timeoutSeconds: TimeInterval) async -> String {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let yandex = URL(string: "https://yandex.com/")!
        var ticks = 0
        while Date() < deadline {
            let cookies = HTTPCookieStorage.shared.cookies(for: yandex) ?? []
            if cookies.contains(where: { $0.name == "Session_id" }) {
                let names = cookies.map { $0.name }.sorted().joined(separator: ",")
                return "found after \(ticks*150)ms (cookies=\(cookies.count) names=\(names))"
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            ticks += 1
        }
        let cookies = HTTPCookieStorage.shared.cookies(for: yandex) ?? []
        let names = cookies.map { $0.name }.sorted().joined(separator: ",")
        return "TIMEOUT after \(Int(timeoutSeconds*1000))ms (cookies=\(cookies.count) names=\(names))"
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

    struct FeedPage {
        let games: [Game]
        let nextPageId: String?
        let hasNext: Bool
    }

    /// Block-aware /feed/ caller for Home. Returns the editorial block list
    /// plus a deduped flat list and the genre vocabulary harvested from
    /// `siteNavigationLinks.categories`. Same query params as `fetchFeed` so
    /// the response shape matches; the only difference is preservation of
    /// block structure on the client side.
    func fetchFeedWithBlocks(gamesPerPage: Int = 24, lang: String = "en") async throws -> FeedWithBlocks {
        var components = URLComponents(string: "https://yandex.com/games/api/catalogue/v2/feed/")!
        components.queryItems = [
            URLQueryItem(name: "with_promos", value: "true"),
            URLQueryItem(name: "lang", value: lang),
            URLQueryItem(name: "games_count", value: String(gamesPerPage)),
            URLQueryItem(name: "categorized_size", value: "5"),
            URLQueryItem(name: "with_recent_games", value: "true"),
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "client_width", value: "390"),
            URLQueryItem(name: "client_height", value: "844"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [[String: Any]]
        else { return FeedWithBlocks(blocks: [], flatGames: [], genres: [], nextPageId: nil, hasNext: false) }
        var blocks: [FeedBlock] = []
        var seen = Set<Int64>()
        var flat: [Game] = []
        for raw in feed {
            guard let type = raw["type"] as? String else { continue }
            let size = raw["size"] as? String
            let title = (raw["title"] as? String) ?? ""
            let items = ((raw["items"] as? [[String: Any]]) ?? []).compactMap(GameDecoder.parse)
            if items.isEmpty { continue }
            blocks.append(FeedBlock(type: type, size: size, title: title, items: items))
            for g in items where seen.insert(g.appId).inserted { flat.append(g) }
        }
        let pageInfo = root["pageInfo"] as? [String: Any]
        let nextPageId = pageInfo?["nextPageId"] as? String
        let hasNext = (pageInfo?["hasNextPage"] as? Bool) ?? (nextPageId != nil)
        let nav = root["siteNavigationLinks"] as? [String: Any]
        let cats = ((nav?["categories"] as? [[String: Any]]) ?? []).compactMap {
            ($0["title"] as? String) ?? ($0["name"] as? String)
        }
        return FeedWithBlocks(
            blocks: blocks,
            flatGames: flat,
            genres: cats,
            nextPageId: nextPageId,
            hasNext: hasNext,
        )
    }

    /// Pulls a single feed page in legacy (flat) form. Phase 2 keeps this for
    /// Browse pagination; Phase 3 may unify with the block-aware caller.
    func fetchFeed(pageId: String?, gamesPerPage: Int = 24, lang: String = "en") async throws -> FeedPage {
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

    private static var preferredYandexHost: String {
        let lang = Locale.preferredLanguages.first ?? Locale.current.identifier
        return lang.hasPrefix("ru") ? "yandex.ru" : "yandex.com"
    }

    private func fetchProfile(lang: String = "en") async throws -> UserProfile {
        // Match the AuthView retpath so the SSR we hit is the same domain
        // that received Set-Cookie:Session_id during auth — yandex.ru for
        // Russian users, yandex.com for the rest. Avoids a yandex.com →
        // yandex.ru geo-redirect that would otherwise drop session context
        // (Session_id is domain-bound on Yandex's side).
        let host = Self.preferredYandexHost
        let preferredLang = host == "yandex.ru" ? "ru" : lang
        var components = URLComponents(string: "https://\(host)/games/")!
        components.queryItems = [URLQueryItem(name: "lang", value: preferredLang)]
        let url = components.url!
        var request = URLRequest(url: url)
        request.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        // Build a merged Cookie header from EVERY yandex.* cookie. Reason:
        // PWL passport (the new passwordless login flow) only sets
        // Session_id on `.yandex.com`. Russian-IP users get geo-redirected
        // to `yandex.ru`, and URLSession's default cookie store does NOT
        // carry `.yandex.com` cookies onto the `.yandex.ru` redirect — the
        // server then sees an anonymous request and the SSR returns
        // userData.uid="". By bypassing the cookie store and shipping the
        // full Cookie header manually, we keep the session intact across
        // the geo-redirect.
        request.httpShouldHandleCookies = false
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        let yandexCookies = allCookies.filter { $0.domain.contains("yandex") }
        // Last-seen-wins dedupe (cookies for both .com and .ru domains often
        // share names; the freshest value is what passport just set).
        var dedup: [String: HTTPCookie] = [:]
        for c in yandexCookies { dedup[c.name] = c }
        let cookieHeader = dedup.values.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        let mergedNames = dedup.keys.sorted().joined(separator: ",")
        Log.write("profile", "fetch begin url=\(url) merged=\(dedup.count)[\(mergedNames)]")

        let delegate = ProfileFetchRedirectDelegate(cookieHeader: cookieHeader)
        let (data, response) = try await URLSession.shared.data(for: request, delegate: delegate)
        let http = response as? HTTPURLResponse
        let finalUrl = (http?.url?.absoluteString) ?? "?"
        Log.write("profile", "fetch http status=\(http?.statusCode ?? -1) bodyLen=\(data.count) finalUrl=\(finalUrl) hops=\(delegate.redirectCount)")
        guard let html = String(data: data, encoding: .utf8) else {
            Log.write("profile", "non-UTF8 body")
            return .anonymous
        }
        guard let json = extractAppData(html) else {
            let preview = String(html.prefix(200)).replacingOccurrences(of: "\n", with: " ")
            Log.write("profile", "NO __appData__ found (htmlLen=\(html.count) preview=\(preview))")
            return .anonymous
        }
        guard let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            Log.write("profile", "appData not a JSON object")
            return .anonymous
        }
        guard let userData = parsed["userData"] as? [String: Any] else {
            let topKeys = parsed.keys.sorted().prefix(20).joined(separator: ",")
            Log.write("profile", "no userData key (topKeys=\(topKeys))")
            return .anonymous
        }
        let uid = (userData["uid"] as? String) ?? ""
        let login = (userData["login"] as? String) ?? ""
        let authProvider = (userData["authProvider"] as? String) ?? ""
        Log.write("profile", "userData uid=\(uid.isEmpty ? "<empty>" : uid) login=\(login) authProvider=\(authProvider)")
        guard !uid.isEmpty else { return .anonymous }
        let avatarsOrigin = (userData["avatarsOrigin"] as? String) ?? "https://avatars.mds.yandex.net"
        let avatarId = (userData["avatarId"] as? String) ?? "0/0-0"
        let avatarUrl = avatarId == "0/0-0" ? "" : "\(avatarsOrigin)/get-yapic/\(avatarId)/islands-300"
        return UserProfile(
            isAuthorized: true,
            displayName: (userData["displayName"] as? String) ?? "",
            login: login,
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

/// Forwards a custom merged Cookie header onto every redirect target so the
/// authenticated session survives `yandex.com → yandex.ru` geo-redirects.
/// PWL passport only sets `Session_id` on `.yandex.com`; the default
/// URLSession cookie store would not attach it to the `.yandex.ru` redirect.
final class ProfileFetchRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let cookieHeader: String
    private(set) var redirectCount: Int = 0

    init(cookieHeader: String) { self.cookieHeader = cookieHeader }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirectCount += 1
        var modified = request
        modified.httpShouldHandleCookies = false
        if !cookieHeader.isEmpty {
            modified.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        completionHandler(modified)
    }
}

enum GameDecoder {
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

    static func parse(_ item: [String: Any]) -> Game? {
        guard let appId = (item["appID"] as? NSNumber)?.int64Value,
              let title = item["title"] as? String else { return nil }
        let rating = (item["rating"] as? NSNumber)?.doubleValue ?? 0
        let ratingCount = (item["ratingCount"] as? NSNumber)?.intValue ?? 0
        let media = item["media"] as? [String: Any]
        let cover = (media?["cover"] as? [String: Any])?["prefix-url"] as? String
        let icon = (media?["icon"] as? [String: Any])?["prefix-url"] as? String
        let coverObj = media?["cover"] as? [String: Any]
        let iconObj = media?["icon"] as? [String: Any]
        let mainColor = coverObj?["mainColor"] as? String
        let iconMainColor = iconObj?["mainColor"] as? String
        let videos = media?["videos"] as? [[String: Any]]
        let videoUrl = videos?.first?["mp4StreamUrl"] as? String
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
            developer: developer,
            mainColor: mainColor,
            iconMainColor: iconMainColor,
            videoUrl: videoUrl
        )
    }
}
