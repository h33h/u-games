import Foundation

struct UserInfoEndpointService {
    let networkService: NetworkService

    func profile() async throws -> ProfileResponseDTO {
        try await networkService.execute(UserInfoRequest(), attempts: 1)
    }
}

struct UserInfoRequest: Request {
    typealias DTO = ProfileResponseDTO

    var path: String { "/games/api/catalogue/v2/user_info" }
}
