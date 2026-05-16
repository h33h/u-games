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
        return decoded.feedWithBlocks
    }

    func feedPage(from data: Data) -> FeedPage {
        guard let decoded = decode(FeedResponseDTO.self, from: data) else {
            return FeedPage(games: [], nextPageId: nil, hasNext: false)
        }
        return decoded.feedPage
    }

    func similarGames(from data: Data) -> [Game] {
        guard let decoded = decode(SimilarGamesResponseDTO.self, from: data) else { return [] }
        return decoded.gamesDomain
    }

    func categories(fromTags data: Data) -> [GameCategory] {
        decode(TagsResponseDTO.self, from: data)?.categories ?? []
    }

    func appDetail(fromGetGame data: Data) -> AppDetail? {
        decode(GetGameResponseDTO.self, from: data)?.appDetail
    }

    func userProfile(from data: Data) -> UserProfile? {
        decode(ProfileResponseDTO.self, from: data)?.userProfile
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
