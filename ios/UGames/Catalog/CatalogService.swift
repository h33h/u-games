import Foundation
import Combine

@MainActor
final class CatalogService: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    func loadInitial() async {
        if !games.isEmpty { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            games = try await fetchFeed(skip: 0)
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
        return try parseFeed(data)
    }

    private func parseFeed(_ data: Data) throws -> [Game] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [[String: Any]] else {
            return []
        }
        var seen = Set<Int64>()
        var out: [Game] = []
        for block in feed {
            guard let items = block["items"] as? [[String: Any]] else { continue }
            for item in items {
                guard let game = parseItem(item) else { continue }
                if seen.insert(game.appId).inserted {
                    out.append(game)
                }
            }
        }
        return out
    }

    private func parseItem(_ item: [String: Any]) -> Game? {
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
