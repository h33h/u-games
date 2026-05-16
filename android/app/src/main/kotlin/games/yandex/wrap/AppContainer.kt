package games.yandex.wrap

import android.content.Context
import games.yandex.wrap.catalog.CatalogApi
import games.yandex.wrap.catalog.CatalogHtmlParser
import games.yandex.wrap.catalog.CatalogJsonParser
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.FavoritesRepository
import games.yandex.wrap.catalog.ProfileRepository
import games.yandex.wrap.catalog.YandexHttpClient
import games.yandex.wrap.catalog.YandexSessionStore
import games.yandex.wrap.config.AppConfig
import games.yandex.wrap.data.AppDatabase
import io.ktor.client.HttpClient

class AppContainer(
    context: Context,
    ktor: HttpClient,
    val config: AppConfig = AppConfig.defaultForLocale(),
) {
    val database: AppDatabase by lazy { AppDatabase.create(context) }
    val jsonParser: CatalogJsonParser by lazy { CatalogJsonParser() }
    val htmlParser: CatalogHtmlParser by lazy { CatalogHtmlParser() }
    val sessionStore: YandexSessionStore by lazy { YandexSessionStore(config) }
    val yandexHttpClient: YandexHttpClient by lazy { YandexHttpClient(ktor, config) }
    val catalogApi: CatalogApi by lazy {
        CatalogApi(
            http = yandexHttpClient,
            jsonParser = jsonParser,
            htmlParser = htmlParser,
            sessionStore = sessionStore,
            config = config,
        )
    }
    val catalogRepository: CatalogRepository by lazy { CatalogRepository(catalogApi, database.gameCacheDao()) }
    val favoritesRepository: FavoritesRepository by lazy { FavoritesRepository(database.favoritesDao()) }
    val profileRepository: ProfileRepository by lazy { ProfileRepository(catalogApi, sessionStore) }
}
