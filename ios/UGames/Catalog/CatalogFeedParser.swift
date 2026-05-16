import Foundation

protocol CatalogParsing {
    func feedWithBlocks(from data: Data) -> FeedWithBlocks
    func feedPage(from data: Data) -> FeedPage
    func similarGames(from data: Data) -> [Game]
    func categories(fromTags data: Data) -> [GameCategory]
    func appDetail(fromGetGame data: Data) -> AppDetail?
    func userProfile(from data: Data) -> UserProfile?
}

struct YandexCatalogJsonParser: CatalogParsing {
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = YandexCatalogJsonParser.makeDecoder()) {
        self.decoder = decoder
    }

    func feedWithBlocks(from data: Data) -> FeedWithBlocks {
        guard let decoded = decode(FeedResponseDTO.self, from: data) else {
            return FeedWithBlocks(blocks: [], flatGames: [], recentGames: [], genres: [], nextPageId: nil, hasNext: false)
        }
        let blocks = decoded.feed.orEmpty.map { $0.domain }
        return FeedWithBlocks(
            blocks: blocks,
            flatGames: blocks.flatMap { $0.items },
            recentGames: decoded.recentGames.orEmpty.map { $0.domain },
            genres: [],
            nextPageId: decoded.pageInfo?.nextPageId,
            hasNext: decoded.pageInfo?.hasNextPage ?? (decoded.pageInfo?.nextPageId != nil)
        )
    }

    func feedPage(from data: Data) -> FeedPage {
        guard let decoded = decode(FeedResponseDTO.self, from: data) else {
            return FeedPage(games: [], nextPageId: nil, hasNext: false)
        }
        return FeedPage(
            games: decoded.feed.orEmpty.flatMap { $0.items.orEmpty.map { $0.domain } },
            nextPageId: decoded.pageInfo?.nextPageId,
            hasNext: decoded.pageInfo?.hasNextPage ?? (decoded.pageInfo?.nextPageId != nil)
        )
    }

    func similarGames(from data: Data) -> [Game] {
        guard let decoded = decode(SimilarGamesResponseDTO.self, from: data) else { return [] }
        if let games = decoded.games {
            return games.map { $0.domain }
        }
        return decoded.feed.orEmpty.flatMap { $0.items.orEmpty.map { $0.domain } }
    }

    func categories(fromTags data: Data) -> [GameCategory] {
        decode(TagsResponseDTO.self, from: data)?.tags.orEmpty.compactMap { tag in
            guard !tag.slug.isEmpty, !tag.title.isEmpty else { return nil }
            return GameCategory(name: tag.slug, title: tag.title, gamesCount: tag.info?.gamesCount ?? 0)
        } ?? []
    }

    func appDetail(fromGetGame data: Data) -> AppDetail? {
        guard let game = decode(GetGameResponseDTO.self, from: data)?.game else { return nil }
        return AppDetail(
            description: game.description,
            screenshots: game.media?.screenshots.orEmpty.values.flatMap { $0 }.compactMap { $0.prefixUrl ?? $0.url } ?? [],
            datePublished: game.datePublished,
            genres: game.categoriesNames.orEmpty,
            languages: game.inLanguage.orEmpty,
            author: game.developer?.name
        )
    }

    func userProfile(from data: Data) -> UserProfile? {
        guard let userData = decode(ProfileResponseDTO.self, from: data)?.userData,
              !userData.uid.isEmpty
        else { return nil }
        return UserProfile(
            isAuthorized: true,
            displayName: userData.displayName ?? "",
            login: userData.login ?? "",
            avatarUrl: userData.avatarUrl ?? "",
            hasYaPlus: userData.yaplusEnabled ?? false
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { codingPath in
            let raw = codingPath.last?.stringValue ?? ""
            return AnyCodingKey(stringValue: raw.normalizedJSONKey)
        }
        return decoder
    }
}
