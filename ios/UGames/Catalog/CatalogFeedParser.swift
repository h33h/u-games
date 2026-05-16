import Foundation

enum CatalogFeedParser {
    static func feedWithBlocks(from root: [String: Any]) -> FeedWithBlocks {
        guard let feed = root["feed"] as? [[String: Any]] else {
            return FeedWithBlocks(blocks: [], flatGames: [], recentGames: [], genres: [], nextPageId: nil, hasNext: false)
        }
        var blocks: [FeedBlock] = []
        for raw in feed {
            guard let type = raw["type"] as? String else { continue }
            let size = raw["size"] as? String
            let title = (raw["title"] as? String) ?? ""
            let items = ((raw["items"] as? [[String: Any]]) ?? []).compactMap(GameDecoder.parse).stableSorted()
            if items.isEmpty { continue }
            blocks.append(FeedBlock(type: type, size: size, title: title, items: items))
        }
        let flat = blocks.flatMap { $0.items }.dedupeBy { $0.appId }
        let page = pageInfo(from: root)
        let recentGames = ((root["recentGames"] as? [[String: Any]]) ?? []).compactMap(GameDecoder.parse)
        return FeedWithBlocks(
            blocks: blocks,
            flatGames: flat.stableSorted(),
            recentGames: recentGames,
            genres: [],
            nextPageId: page.nextPageId,
            hasNext: page.hasNext,
        )
    }

    static func feedPage(from root: [String: Any]) -> FeedPage {
        guard let feed = root["feed"] as? [[String: Any]] else {
            return FeedPage(games: [], nextPageId: nil, hasNext: false)
        }
        let page = pageInfo(from: root)
        return FeedPage(games: GameDecoder.flatten(feed), nextPageId: page.nextPageId, hasNext: page.hasNext)
    }

    static func similarGames(from root: [String: Any]) -> [Game] {
        if let games = root["games"] as? [[String: Any]] {
            var seen = Set<Int64>()
            var out: [Game] = []
            for item in games {
                guard let game = GameDecoder.parse(item) else { continue }
                if seen.insert(game.appId).inserted { out.append(game) }
            }
            return out.stableSorted()
        }
        if let feed = root["feed"] as? [[String: Any]] {
            return GameDecoder.flatten(feed)
        }
        return []
    }

    private static func pageInfo(from root: [String: Any]) -> (nextPageId: String?, hasNext: Bool) {
        let pageInfo = root["pageInfo"] as? [String: Any]
        let nextPageId = pageInfo?["nextPageId"] as? String
        let hasNext = (pageInfo?["hasNextPage"] as? Bool) ?? (nextPageId != nil)
        return (nextPageId, hasNext)
    }
}

extension Array where Element == Game {
    func stableSorted() -> [Game] {
        sorted { a, b in
            if a.ratingCount != b.ratingCount { return a.ratingCount > b.ratingCount }
            if a.rating != b.rating { return a.rating > b.rating }
            if a.title != b.title { return a.title.localizedCompare(b.title) == .orderedAscending }
            return a.appId < b.appId
        }
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
        return out.stableSorted()
    }

    static func parse(_ item: [String: Any]) -> Game? {
        guard let appId = (item["appID"] as? NSNumber)?.int64Value,
              let title = item["title"] as? String else { return nil }
        let rating = (item["rating"] as? NSNumber)?.doubleValue ?? 0
        let ratingCount = (item["ratingCount"] as? NSNumber)?.intValue ?? 0
        let media = item["media"] as? [String: Any]
        let coverObj = media?["cover"] as? [String: Any]
        let iconObj = media?["icon"] as? [String: Any]
        let cover = coverObj?["prefix-url"] as? String
        let icon = iconObj?["prefix-url"] as? String
        let videos = media?["videos"] as? [[String: Any]]
        let ageRating = ((item["features"] as? [String: Any])?["age_rating"] as? String)?
            .trimmingCharacters(in: .whitespaces)
        return Game(
            appId: appId,
            title: title,
            rating: rating,
            ratingCount: ratingCount,
            coverUrl: cover.map { "\($0)pjpg250x140" } ?? "",
            iconUrl: (icon ?? cover).map { "\($0)pjpg256x256" } ?? "",
            categories: (item["categoriesNames"] as? [String]) ?? [],
            developer: (item["developer"] as? [String: Any])?["name"] as? String ?? "",
            mainColor: coverObj?["mainColor"] as? String,
            iconMainColor: iconObj?["mainColor"] as? String,
            videoUrl: videos?.first?["mp4StreamUrl"] as? String,
            coverPrefixUrl: cover,
            ageRating: (ageRating?.isEmpty == true) ? nil : ageRating
        )
    }
}
