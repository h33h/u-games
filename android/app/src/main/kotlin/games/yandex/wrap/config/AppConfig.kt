package games.yandex.wrap.config

import java.net.URI
import java.util.Locale

enum class YandexHost(val host: String) {
    Com("yandex.com"),
    Ru("yandex.ru"),
}

data class HttpDefaults(
    val userAgent: String,
    val acceptLanguage: String = "en-US,en;q=0.9",
)

data class YandexEndpoints(
    val preferredHost: YandexHost,
    val apiHost: YandexHost = YandexHost.Com,
    val platform: String = "android_other",
    val clientWidth: Int = 412,
    val clientHeight: Int = 915,
) {
    fun origin(host: YandexHost = preferredHost): URI = URI("https://${host.host}")
    fun gamesHome(host: YandexHost = preferredHost): URI = URI("https://${host.host}/games/")
    fun passportOrigin(): URI = URI("https://${if (preferredHost == YandexHost.Ru) "passport.yandex.ru" else "passport.yandex.com"}")
    fun authUrl(): URI = URI("${passportOrigin()}/auth?retpath=${gamesHome().toString().urlEncoded()}")
    fun gameUrl(appId: Long, host: YandexHost = apiHost): URI = URI("https://${host.host}/games/app/$appId")
    fun feedApi(): URI = URI("https://${apiHost.host}/games/api/catalogue/v2/feed/")
    fun searchApi(): URI = URI("https://${apiHost.host}/games/api/catalogue/v2/search/")
    fun similarApi(): URI = URI("https://${apiHost.host}/games/api/catalogue/v2/similar_games/")
    fun searchPage(): URI = URI("https://${apiHost.host}/games/search")

    fun isGamesUrl(url: String): Boolean =
        url.startsWith(gamesHome(YandexHost.Com).toString()) || url.startsWith(gamesHome(YandexHost.Ru).toString())

    fun documentStartOrigins(): Set<String> = setOf(
        "https://${YandexHost.Com.host}",
        "https://${YandexHost.Ru.host}",
    )

    fun logBridgeOrigins(): Set<String> = documentStartOrigins() + setOf(
        passportOriginFor(YandexHost.Com),
        passportOriginFor(YandexHost.Ru),
        "https://*.games.s3.yandex.net",
        "https://*.cdn.games.yandex.net",
        "https://*.gamecdn.yandex.net",
        "https://*.game-static.ru",
        "https://game-static.ru",
    )

    fun cookieDonorOrigins(): List<String> = listOf(
        origin(YandexHost.Com).toString(),
        origin(YandexHost.Ru).toString(),
        passportOriginFor(YandexHost.Com),
        passportOriginFor(YandexHost.Ru),
    )

    fun cookieClearOrigins(): List<String> = cookieDonorOrigins() + listOf(
        "https://games.yandex.com",
        "https://games.yandex.ru",
        "https://id.yandex.com",
    )

    private fun passportOriginFor(host: YandexHost): String =
        "https://${if (host == YandexHost.Ru) "passport.yandex.ru" else "passport.yandex.com"}"
}

data class AppConfig(
    val yandex: YandexEndpoints,
    val http: HttpDefaults,
) {
    companion object {
        fun defaultForLocale(language: String = Locale.getDefault().language): AppConfig {
            val preferred = if (language.lowercase().startsWith("ru")) YandexHost.Ru else YandexHost.Com
            return AppConfig(
                yandex = YandexEndpoints(preferredHost = preferred),
                http = HttpDefaults(
                    userAgent = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36",
                ),
            )
        }
    }
}

private fun String.urlEncoded(): String =
    java.net.URLEncoder.encode(this, Charsets.UTF_8.name())
