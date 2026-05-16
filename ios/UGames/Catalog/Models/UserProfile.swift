import Foundation

struct UserProfile: Equatable {
    var isAuthorized: Bool
    var displayName: String
    var login: String
    var avatarUrl: String
    var hasYaPlus: Bool
}
