package games.yandex.wrap

import android.content.Context
import games.yandex.wrap.catalog.CatalogApi
import games.yandex.wrap.catalog.CatalogParser
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.FavoritesRepository
import games.yandex.wrap.catalog.ProfileRepository
import games.yandex.wrap.catalog.YandexCatalogJsonParser
import games.yandex.wrap.catalog.YandexSessionStore
import games.yandex.wrap.data.AppDatabase
import games.yandex.wrap.network.FeedEndpointService
import games.yandex.wrap.network.GameDetailEndpointService
import games.yandex.wrap.network.NetworkService
import games.yandex.wrap.network.SearchEndpointService
import games.yandex.wrap.network.SimilarGamesEndpointService
import games.yandex.wrap.network.TagsEndpointService
import games.yandex.wrap.network.UserInfoEndpointService
import io.ktor.client.HttpClient

class AppContainer(
    context: Context,
    ktor: HttpClient,
) {
    val database: AppDatabase by lazy { AppDatabase.create(context) }
    val catalogParser: CatalogParser by lazy { YandexCatalogJsonParser() }
    val sessionStore: YandexSessionStore by lazy { YandexSessionStore() }
    val networkService: NetworkService by lazy {
        NetworkService(
            ktor = ktor,
            cookieHeaderProvider = { sessionStore.cookieHeader() },
        )
    }
    val feedEndpointService: FeedEndpointService by lazy { FeedEndpointService(networkService) }
    val searchEndpointService: SearchEndpointService by lazy { SearchEndpointService(networkService) }
    val tagsEndpointService: TagsEndpointService by lazy { TagsEndpointService(networkService) }
    val gameDetailEndpointService: GameDetailEndpointService by lazy { GameDetailEndpointService(networkService) }
    val similarGamesEndpointService: SimilarGamesEndpointService by lazy { SimilarGamesEndpointService(networkService) }
    val userInfoEndpointService: UserInfoEndpointService by lazy { UserInfoEndpointService(networkService) }
    val catalogApi: CatalogApi by lazy {
        CatalogApi(
            feedEndpoint = feedEndpointService,
            searchEndpoint = searchEndpointService,
            tagsEndpoint = tagsEndpointService,
            gameDetailEndpoint = gameDetailEndpointService,
            similarGamesEndpoint = similarGamesEndpointService,
            userInfoEndpoint = userInfoEndpointService,
        )
    }
    val catalogRepository: CatalogRepository by lazy { CatalogRepository(catalogApi, database.gameCacheDao()) }
    val favoritesRepository: FavoritesRepository by lazy { FavoritesRepository(database.favoritesDao()) }
    val profileRepository: ProfileRepository by lazy { ProfileRepository(catalogApi, sessionStore) }
}
