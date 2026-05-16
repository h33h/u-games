import Foundation

struct UserDataDTO: Decodable {
    let uid: String
    let displayName: String?
    let login: String?
    let avatarUrl: String?
    let yaplusEnabled: Bool?
}
