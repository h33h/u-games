import Foundation

struct FeedBlockDTO: Decodable {
    let type: String
    let size: String?
    let title: String?
    let items: [GameDTO]?

    var domain: FeedBlock {
        FeedBlock(type: type, size: size, title: title ?? "", items: items.orEmpty.map { $0.domain })
    }
}
