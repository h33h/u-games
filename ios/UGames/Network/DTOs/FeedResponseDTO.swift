import Foundation

struct FeedResponseDTO: Decodable {
    let feed: [FeedBlockDTO]?
    let items: [GameDTO]?
    let recentGames: [GameDTO]?
    let pageInfo: PageInfoDTO?
    let pageID: String?
    let totalPages: Int?
}
