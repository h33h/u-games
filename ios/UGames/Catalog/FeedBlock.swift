import Foundation

struct FeedBlock: Equatable {
    let type: String
    let size: String?
    let title: String
    let items: [Game]
}

struct FeedWithBlocks: Equatable {
    let blocks: [FeedBlock]
    let flatGames: [Game]
    let recentGames: [Game]
    let genres: [String]
    let nextPageId: String?
    let hasNext: Bool
}

struct GameCategory: Equatable, Identifiable {
    let name: String
    let title: String
    let gamesCount: Int
    var id: String { name }
}
