import Foundation

protocol CatalogParsing {
    func feedWithBlocks(from root: [String: Any]) -> FeedWithBlocks
    func feedPage(from root: [String: Any]) -> FeedPage
    func similarGames(from root: [String: Any]) -> [Game]
    func categories(fromTags root: [String: Any]) -> [GameCategory]
    func appDetail(fromGetGame root: [String: Any]) -> AppDetail?
    func userProfile(from root: [String: Any]) -> UserProfile?
}

struct YandexCatalogJsonParser: CatalogParsing {
    func feedWithBlocks(from root: [String: Any]) -> FeedWithBlocks {
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

    func feedPage(from root: [String: Any]) -> FeedPage {
        guard let feed = root["feed"] as? [[String: Any]] else {
            return FeedPage(games: [], nextPageId: nil, hasNext: false)
        }
        let page = pageInfo(from: root)
        return FeedPage(games: GameDecoder.flatten(feed), nextPageId: page.nextPageId, hasNext: page.hasNext)
    }

    func similarGames(from root: [String: Any]) -> [Game] {
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

    func categories(fromTags root: [String: Any]) -> [GameCategory] {
        guard let tags = root["tags"] as? [[String: Any]] else { return [] }
        return tags.compactMap { item in
            guard let slug = item["slug"] as? String, !slug.isEmpty,
                  let title = item["title"] as? String, !title.isEmpty
            else { return nil }
            let info = item["info"] as? [String: Any]
            return GameCategory(
                name: slug,
                title: title,
                gamesCount: (info?["games_count"] as? NSNumber)?.intValue ?? 0
            )
        }
    }

    func appDetail(fromGetGame root: [String: Any]) -> AppDetail? {
        guard let game = root["game"] as? [String: Any] else { return nil }
        let description = (game["description"] as? String).flatMap {
            let trimmed = Self.decodeHtmlEntities($0).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let media = game["media"] as? [String: Any]
        let screenshots = Self.screenshotUrls(from: media?["screenshots"])
        let genres = ((game["categoriesNames"] as? [String]) ?? []).map(Self.decodeHtmlEntities)
        let languages: [String]
        if let arr = game["inLanguage"] as? [String] {
            languages = arr
        } else if let single = game["inLanguage"] as? String {
            languages = [single]
        } else {
            languages = []
        }
        let author = ((game["developer"] as? [String: Any])?["name"] as? String)
            .map(Self.decodeHtmlEntities)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AppDetail(
            description: description,
            screenshots: screenshots,
            datePublished: (game["datePublished"] as? String) ?? (game["releaseDate"] as? String),
            genres: genres,
            languages: languages,
            author: (author?.isEmpty == false) ? author : nil
        )
    }

    func userProfile(from root: [String: Any]) -> UserProfile? {
        let userData = (root["userData"] as? [String: Any])
            ?? (root["user"] as? [String: Any])
            ?? root
        let uid = (userData["uid"] as? String)
            ?? (userData["id"] as? String)
            ?? (userData["passportUid"] as? String)
            ?? ""
        guard !uid.isEmpty else { return nil }
        let avatarsOrigin = (userData["avatarsOrigin"] as? String) ?? "https://avatars.mds.yandex.net"
        let avatarId = (userData["avatarId"] as? String) ?? "0/0-0"
        let avatarUrl = (userData["avatarUrl"] as? String)
            ?? (avatarId == "0/0-0" ? "" : "\(avatarsOrigin)/get-yapic/\(avatarId)/islands-300")
        return UserProfile(
            isAuthorized: true,
            displayName: (userData["displayName"] as? String) ?? (userData["name"] as? String) ?? "",
            login: (userData["login"] as? String) ?? "",
            avatarUrl: avatarUrl,
            hasYaPlus: ((userData["yaplusEnabled"] as? Bool) ?? false) || ((userData["hasYaPlus"] as? Bool) ?? false)
        )
    }

    private func pageInfo(from root: [String: Any]) -> (nextPageId: String?, hasNext: Bool) {
        let pageInfo = root["pageInfo"] as? [String: Any]
        let nextPageId = pageInfo?["nextPageId"] as? String
        let hasNext = (pageInfo?["hasNextPage"] as? Bool) ?? (nextPageId != nil)
        return (nextPageId, hasNext)
    }

    private static func screenshotUrls(from raw: Any?) -> [String] {
        var urls: [String] = []
        if let arr = raw as? [[String: Any]] {
            urls.append(contentsOf: arr.compactMap(screenshotUrl))
        } else if let dict = raw as? [String: Any] {
            for value in dict.values {
                guard let arr = value as? [[String: Any]] else { continue }
                urls.append(contentsOf: arr.compactMap(screenshotUrl))
            }
        }
        return urls.dedupeBy { $0 }
    }

    private static func screenshotUrl(_ item: [String: Any]) -> String? {
        if let prefix = item["prefix-url"] as? String, !prefix.isEmpty {
            return "\(prefix)pjpg500x280"
        }
        if let url = item["url"] as? String {
            return rewriteAvatarSize(url, newSize: "pjpg500x280")
        }
        return nil
    }

    private static func rewriteAvatarSize(_ url: String, newSize: String) -> String {
        guard let lastSlash = url.lastIndex(of: "/"), lastSlash != url.startIndex else { return url }
        return String(url[..<url.index(after: lastSlash)]) + newSize
    }

    private static func decodeHtmlEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
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
