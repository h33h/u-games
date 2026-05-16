import Foundation

struct SimilarGamesResponseDTO: Decodable {
    let games: [GameDTO]?
    let feed: [FeedBlockDTO]?
}
