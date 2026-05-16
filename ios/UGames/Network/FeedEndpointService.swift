import Foundation

struct FeedEndpointService {
    let networkService: NetworkService

    func feed(
        gamesPerPage: Int = 24,
        pageId: String? = nil
    ) async throws -> FeedResponseDTO {
        try await networkService.execute(
            FeedRequest(
                gamesPerPage: gamesPerPage,
                pageId: pageId
            )
        )
    }

}

struct FeedRequest: Request {
    typealias DTO = FeedResponseDTO

    let gamesPerPage: Int
    let pageId: String?

    var path: String { "/games/api/catalogue/v2/feed/" }

    var queryItems: [URLQueryItem] {
        queryItems([
            ("with_promos", "true"),
            ("games_count", String(gamesPerPage)),
            ("categorized_size", "5"),
            ("with_recent_games", "true"),
            ("platform", "ios"),
            ("client_width", String(Int(Constants.UI.screenSize.width.rounded()))),
            ("client_height", String(Int(Constants.UI.screenSize.height.rounded()))),
            ("page_id", pageId),
        ])
    }
}
