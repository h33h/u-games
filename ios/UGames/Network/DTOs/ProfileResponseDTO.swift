import Foundation

struct ProfileResponseDTO: Decodable {
    let uid: String?
    let displayName: String?
    let login: String?
    let avatarId: String?
    let avatarsOrigin: String?
    let yaplusEnabled: Bool?
}
