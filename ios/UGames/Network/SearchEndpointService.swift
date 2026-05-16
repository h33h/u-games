import Foundation

struct SearchEndpointService {
    let networkService: NetworkService

    func search(
        query: String,
        pageId: String? = nil,
        gamesPerPage: Int = 24
    ) async throws -> FeedResponseDTO {
        try await networkService.execute(SearchRequest(query: query, pageId: pageId, gamesPerPage: gamesPerPage))
    }
}

struct SearchRequest: Request {
    typealias DTO = FeedResponseDTO

    let query: String
    let pageId: String?
    let gamesPerPage: Int

    var path: String { "/games/api/catalogue/v2/search/" }

    var queryItems: [URLQueryItem] {
        queryItems([
            ("query", query),
            ("platform", "ios"),
            ("games_count", String(gamesPerPage)),
            ("page_id", pageId),
        ])
    }
}
