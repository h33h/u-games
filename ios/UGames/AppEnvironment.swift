import Foundation

struct AppEnvironment {
    let config: AppConfig
    let remote: YandexCatalogRemoteDataSource
    let sessionStore: YandexSessionStore

    static let live: AppEnvironment = {
        let config = AppConfig.live()
        let http = CatalogHTTPClient(config: config)
        let sessionStore = YandexSessionStore(config: config)
        return AppEnvironment(
            config: config,
            remote: YandexCatalogRemoteDataSource(config: config, http: http),
            sessionStore: sessionStore
        )
    }()
}
