import Foundation

struct GameDetailEndpointService {
    let networkService: NetworkService

    func detail(appId: Int64) async throws -> GetGameResponseDTO {
        try await networkService.execute(GameDetailRequest(appId: appId))
    }
}

struct GameDetailRequest: Request {
    typealias DTO = GetGameResponseDTO

    let appId: Int64

    var method: HTTPMethod { .post }
    var path: String { "/games/api/catalogue/v2/get_game" }
    var body: Data? {
        json(["appID": appId, "format": "app"])
    }
}
