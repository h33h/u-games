import Foundation

struct TagsEndpointService {
    let networkService: NetworkService

    func tags() async throws -> TagsResponseDTO {
        try await networkService.execute(TagsRequest())
    }
}

struct TagsRequest: Request {
    typealias DTO = TagsResponseDTO

    var path: String { "/games/api/catalogue/v2/tags/" }
}
