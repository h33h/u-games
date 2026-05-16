import Foundation

struct SimilarGamesEndpointService {
    let networkService: NetworkService

    func similar(appId: Int64) async throws -> SimilarGamesResponseDTO {
        try await networkService.execute(SimilarGamesRequest(appId: appId))
    }
}

struct SimilarGamesRequest: Request {
    typealias DTO = SimilarGamesResponseDTO

    let appId: Int64

    var path: String { "/games/api/catalogue/v2/similar_games/" }

    var queryItems: [URLQueryItem] {
        queryItems([
            ("app_id", String(appId)),
            ("games_count", "16"),
            ("int", "true"),
            ("page_type", "game"),
            ("platform", "ios"),
            ("standalone", "false"),
        ])
    }
}
