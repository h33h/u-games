import Foundation

struct FeedBlockDTO: Decodable {
    let type: String
    let size: String?
    let title: String?
    let items: [GameDTO]?
}
