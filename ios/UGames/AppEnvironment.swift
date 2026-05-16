import Foundation

struct AppEnvironment {
    let remote: YandexCatalogRemoteDataSource
    let sessionStore: YandexSessionStore

    static let live: AppEnvironment = {
        let sessionStore = YandexSessionStore()
        let networkService = NetworkService(cookieHeaderProvider: {
            sessionStore.cookieHeader().header
        })
        return AppEnvironment(
            remote: YandexCatalogRemoteDataSource(networkService: networkService),
            sessionStore: sessionStore
        )
    }()
}
