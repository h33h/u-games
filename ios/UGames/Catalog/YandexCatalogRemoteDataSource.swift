import Foundation

struct YandexCatalogRemoteDataSource {
    let feedEndpoint: FeedEndpointService
    let searchEndpoint: SearchEndpointService
    let tagsEndpoint: TagsEndpointService
    let gameDetailEndpoint: GameDetailEndpointService
    let similarGamesEndpoint: SimilarGamesEndpointService
    let userInfoEndpoint: UserInfoEndpointService

    init(networkService: NetworkService) {
        self.feedEndpoint = FeedEndpointService(networkService: networkService)
        self.searchEndpoint = SearchEndpointService(networkService: networkService)
        self.tagsEndpoint = TagsEndpointService(networkService: networkService)
        self.gameDetailEndpoint = GameDetailEndpointService(networkService: networkService)
        self.similarGamesEndpoint = SimilarGamesEndpointService(networkService: networkService)
        self.userInfoEndpoint = UserInfoEndpointService(networkService: networkService)
    }

    func fetchFeedWithBlocks(
        gamesPerPage: Int = 24,
        tab: String? = nil
    ) async throws -> FeedWithBlocks {
        try await feedEndpoint.feed(
            gamesPerPage: gamesPerPage
        ).feedWithBlocks
    }

    func fetchSearchPaginated(
        query: String,
        pageId: String? = nil,
        gamesPerPage: Int = 24
    ) async throws -> FeedPage {
        try await searchEndpoint.search(
            query: query,
            pageId: pageId,
            gamesPerPage: gamesPerPage
        ).feedPage
    }

    func fetchCategories() async throws -> [GameCategory] {
        try await tagsEndpoint.tags().categories
    }

    func fetchFeed(pageId: String?, gamesPerPage: Int = 24) async throws -> FeedPage {
        try await feedEndpoint.feed(
            gamesPerPage: gamesPerPage,
            pageId: pageId
        ).feedPage
    }

    func fetchAppDetail(appId: Int64) async -> AppDetail? {
        do {
            return try await gameDetailEndpoint.detail(appId: appId).appDetail
        } catch {
            return nil
        }
    }

    func fetchSimilar(appId: Int64) async -> [Game] {
        do {
            return try await similarGamesEndpoint.similar(appId: appId).gamesDomain
        } catch {
            return []
        }
    }

    func fetchSearch(query: String) async throws -> [Game] {
        try await searchEndpoint.search(
            query: query,
            gamesPerPage: 24
        ).feedPage.games
    }

    func fetchProfile() async throws -> (UserProfile?, Int, Int, String) {
        let response = try await userInfoEndpoint.profile()
        return (response.userProfile, 0, 0, "")
    }
}
