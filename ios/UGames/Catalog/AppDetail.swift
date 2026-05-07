import Foundation

struct AppDetail: Equatable {
    let description: String?

    let screenshots: [String]

    let datePublished: String?

    let genres: [String]

    let languages: [String]

    let author: String?

    static let empty = AppDetail(
        description: nil, screenshots: [], datePublished: nil,
        genres: [], languages: [], author: nil
    )
}
