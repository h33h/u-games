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
    /// Hex like "#41B4F6". Used for halo glow + image placeholder.
    let mainColor: String?
    /// Hex of the icon's mainColor. Used for square cards (recently row).
    let iconMainColor: String?
    /// Direct mp4 URL from media.videos[0].mp4StreamUrl, for Hero autoplay.
    let videoUrl: String?

    init(
        appId: Int64,
        title: String,
        rating: Double,
        ratingCount: Int,
        coverUrl: String,
        iconUrl: String,
        categories: [String],
        developer: String,
        mainColor: String? = nil,
        iconMainColor: String? = nil,
        videoUrl: String? = nil
    ) {
        self.appId = appId
        self.title = title
        self.rating = rating
        self.ratingCount = ratingCount
        self.coverUrl = coverUrl
        self.iconUrl = iconUrl
        self.categories = categories
        self.developer = developer
        self.mainColor = mainColor
        self.iconMainColor = iconMainColor
        self.videoUrl = videoUrl
    }

    var id: Int64 { appId }

    var playUrl: URL? {
        URL(string: "https://yandex.com/games/app/\(appId)")
    }
}
