import Foundation

struct SpotlightBlock: Equatable {
    let title: String
    let games: [Game]
}

struct GenreRow: Equatable {
    let title: String
    let categoryName: String?
    let games: [Game]
}
