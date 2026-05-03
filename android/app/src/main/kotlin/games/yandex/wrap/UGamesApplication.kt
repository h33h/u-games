package games.yandex.wrap

import android.app.Application
import games.yandex.wrap.catalog.CatalogApi
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.data.AppDatabase
import games.yandex.wrap.webview.BlockList
import games.yandex.wrap.webview.InjectedScripts
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

class UGamesApplication : Application() {

    val httpClient: HttpClient by lazy {
        HttpClient(OkHttp) {
            install(ContentNegotiation) {
                json(Json {
                    ignoreUnknownKeys = true
                    isLenient = true
                    coerceInputValues = true
                })
            }
        }
    }

    val database: AppDatabase by lazy { AppDatabase.create(this) }

    val catalogApi: CatalogApi by lazy { CatalogApi(httpClient) }

    val catalogRepository: CatalogRepository by lazy {
        CatalogRepository(catalogApi, database.gameCacheDao(), database.favoritesDao())
    }

    val injectedScripts: InjectedScripts by lazy { InjectedScripts.load(this) }

    val blockList: BlockList by lazy { BlockList.load(this) }
}
