package games.yandex.wrap

import android.app.Application
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache
import games.yandex.wrap.webview.AndroidWebViewCookieStorage
import games.yandex.wrap.webview.BlockList
import games.yandex.wrap.webview.InjectedScripts
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpRedirect
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

class UGamesApplication : Application(), ImageLoaderFactory {

    val httpClient: HttpClient by lazy {
        HttpClient(OkHttp) {
            install(ContentNegotiation) {
                json(Json {
                    ignoreUnknownKeys = true
                    isLenient = true
                    coerceInputValues = true
                })
            }
            install(HttpCookies) {
                storage = AndroidWebViewCookieStorage()
            }
            install(HttpRedirect) {
                checkHttpMethod = false
            }
        }
    }

    val container: AppContainer by lazy { AppContainer(this, httpClient) }

    val catalogRepository get() = container.catalogRepository
    val favoritesRepository get() = container.favoritesRepository
    val profileRepository get() = container.profileRepository
    val injectedScripts: InjectedScripts by lazy { InjectedScripts.load(this) }

    val blockList: BlockList by lazy { BlockList.load(this) }

    /**
     * Coil picks up `ImageLoaderFactory` automatically (we declare it on
     * the Application class) and uses this loader for every `AsyncImage`
     * call. Defaults are reasonable, but Yandex's avatars URLs are
     * content-hashed (the path includes the asset hash) so the response
     * never goes stale — bumping the disk cache to 250 MB keeps tile
     * thumbnails warm across cold starts, and 25 % memory keeps the
     * scroll-back experience flicker-free without putting pressure on
     * lower-end devices.
     */
    override fun newImageLoader(): ImageLoader =
        ImageLoader.Builder(this)
            .memoryCache {
                MemoryCache.Builder(this)
                    .maxSizePercent(0.25)
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("img_cache"))
                    .maxSizeBytes(250L * 1024 * 1024)
                    .build()
            }
            .respectCacheHeaders(false)
            .crossfade(150)
            .build()
}
