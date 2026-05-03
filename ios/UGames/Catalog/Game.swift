import Foundation

struct Game: Identifiable, Equatable, Hashable, Codable {
    let appId: Int64
    let title: String
    let rating: Double
    let ratingCount: Int
    let coverUrl: String
    let iconUrl: String
    let categories: [String]
    let developer: String

    var id: Int64 { appId }

    var playUrl: URL? {
        URL(string: "https://yandex.com/games/app/\(appId)")
    }
}
