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

    var domain: Game {
        let coverPrefix = media?.cover?.prefixUrl
        let iconPrefix = media?.icon?.prefixUrl
        return Game(
            appId: appID,
            title: title,
            rating: rating ?? 0,
            ratingCount: ratingCount ?? 0,
            coverUrl: coverPrefix ?? "",
            iconUrl: iconPrefix ?? coverPrefix ?? "",
            categories: categoriesNames.orEmpty,
            developer: developer?.name ?? "",
            mainColor: media?.cover?.mainColor,
            iconMainColor: media?.icon?.mainColor,
            videoUrl: media?.videos.orEmpty.first?.mp4StreamUrl,
            coverPrefixUrl: coverPrefix,
            ageRating: features?.ageRating
        )
    }
}
