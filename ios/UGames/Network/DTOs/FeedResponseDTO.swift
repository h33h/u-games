import Foundation

struct FeedResponseDTO: Decodable {
    let feed: [FeedBlockDTO]?
    let recentGames: [GameDTO]?
    let pageInfo: PageInfoDTO?
}
