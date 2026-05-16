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

    let mainColor: String?

    let iconMainColor: String?

    let videoUrl: String?

    let coverPrefixUrl: String?

    let ageRating: String?

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
        videoUrl: String? = nil,
        coverPrefixUrl: String? = nil,
        ageRating: String? = nil
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
        self.coverPrefixUrl = coverPrefixUrl
        self.ageRating = ageRating
    }

    var id: Int64 { appId }

    var playUrl: URL? {
        URL(string: "https://yandex.ru/games/app/\(appId)")
    }

    func coverUrl(size: String) -> String {
        if let p = coverPrefixUrl { return p + size }
        if coverUrl.hasSuffix("/") { return coverUrl + size }
        return coverUrl
    }

    func iconUrl(size: String) -> String {
        if iconUrl.hasSuffix("/") { return iconUrl + size }
        return iconUrl.isEmpty ? coverUrl(size: size) : iconUrl
    }
}
