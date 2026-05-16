import Foundation

struct FeedPage: Equatable {
    let games: [Game]
    let nextPageId: String?
    let hasNext: Bool
}
