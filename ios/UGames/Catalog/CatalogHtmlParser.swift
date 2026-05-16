import Foundation

enum CatalogHtmlParser {
    static func categories(fromAppData json: String) -> [GameCategory] {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let raw = parsed["categoriesForTabs"] as? [[String: Any]]
        else { return [] }
        return raw.compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty,
                  let title = item["title"] as? String, !title.isEmpty
            else { return nil }
            return GameCategory(name: name, title: title, gamesCount: (item["gamesCount"] as? Int) ?? 0)
        }
    }

    static func userProfile(fromAppData json: String) -> UserProfile? {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let userData = parsed["userData"] as? [String: Any]
        else { return nil }
        let uid = (userData["uid"] as? String) ?? ""
        guard !uid.isEmpty else { return nil }
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

    static func appDetail(fromJsonLd json: String) -> AppDetail? {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let graph = parsed["@graph"] as? [[String: Any]],
              let game = graph.first(where: {
                  let type = $0["@type"] as? String
                  return type == "SoftwareApplication" || type == "VideoGame" || type == "MobileApplication"
              })
        else { return nil }
        let mainEntity = game["mainEntityOfPage"] as? [String: Any]
        let rawDesc = (mainEntity?["description"] as? String) ?? (game["description"] as? String)
        let description = rawDesc.flatMap {
            let trimmed = decodeHtmlEntities($0).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let screenshots = ((game["screenshot"] as? [[String: Any]]) ?? [])
            .compactMap { $0["url"] as? String }
            .map { rewriteAvatarSize($0, newSize: "pjpg500x280") }
        let genres: [String]
        if let arr = game["genre"] as? [String] {
            genres = arr.map(Self.decodeHtmlEntities)
        } else if let single = game["genre"] as? String {
            genres = [Self.decodeHtmlEntities(single)]
        } else {
            genres = []
        }
        let languages: [String]
        if let arr = game["inLanguage"] as? [String] {
            languages = arr
        } else if let single = game["inLanguage"] as? String {
            languages = [single]
        } else {
            languages = []
        }
        let author = ((game["author"] as? [String: Any])?["name"] as? String)
            .map(Self.decodeHtmlEntities)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AppDetail(
            description: description,
            screenshots: screenshots,
            datePublished: game["datePublished"] as? String,
            genres: genres,
            languages: languages,
            author: (author?.isEmpty == false) ? author : nil
        )
    }

    static func extractAppData(_ html: String) -> String? {
        guard let markerRange = html.range(of: "id=\"__appData__\"") else { return nil }
        guard let openIdx = html.range(of: ">", range: markerRange.upperBound..<html.endIndex) else { return nil }
        guard let closeIdx = html.range(of: "</script>", range: openIdx.upperBound..<html.endIndex) else { return nil }
        return String(html[openIdx.upperBound..<closeIdx.lowerBound])
    }

    static func extractJsonLd(_ html: String) -> String? {
        let markers = ["type=\"application/ld+json\"", "type='application/ld+json'"]
        for marker in markers {
            guard let markerRange = html.range(of: marker) else { continue }
            guard let openIdx = html.range(of: ">", range: markerRange.upperBound..<html.endIndex) else { continue }
            guard let closeIdx = html.range(of: "</script>", range: openIdx.upperBound..<html.endIndex) else { continue }
            return String(html[openIdx.upperBound..<closeIdx.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
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
