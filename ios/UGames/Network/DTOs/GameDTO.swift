import Foundation

struct GameDTO: Decodable {
    let appID: Int64
    let title: String
    let rating: Double?
    let ratingCount: Int?
    let media: GameMediaDTO?
    let categoriesNames: [String]?
    let developer: NamedDTO?
    let features: GameFeaturesDTO?
}
