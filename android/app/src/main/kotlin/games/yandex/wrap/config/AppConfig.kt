package games.yandex.wrap.config

import java.net.URI

data class HttpDefaults(
    val userAgent: String,
    val acceptLanguage: String = "en-US,en;q=0.9",
)

data class YandexEndpoints(
    val platform: String = "android_other",
    val clientWidth: Int = 412,
    val clientHeight: Int = 915,
) {
    fun origin(): URI = URI("https://$YANDEX_HOST")
    fun gamesHome(): URI = URI("https://$YANDEX_HOST/games/")
    fun passportOrigin(): URI = URI("https://passport.$YANDEX_HOST")
    fun authUrl(): URI = URI("${passportOrigin()}/auth?retpath=${gamesHome().toString().urlEncoded()}")
    fun gameUrl(appId: Long): URI = URI("https://$YANDEX_HOST/games/app/$appId")
    fun feedApi(): URI = URI("https://$YANDEX_HOST/games/api/catalogue/v2/feed/")
    fun searchApi(): URI = URI("https://$YANDEX_HOST/games/api/catalogue/v2/search/")
    fun similarApi(): URI = URI("https://$YANDEX_HOST/games/api/catalogue/v2/similar_games/")
    fun gameDetailApi(): URI = URI("https://$YANDEX_HOST/games/api/catalogue/v2/get_game")
    fun tagsApi(): URI = URI("https://$YANDEX_HOST/games/api/catalogue/v2/tags/")
    fun userInfoApi(): URI = URI("https://$YANDEX_HOST/games/api/catalogue/v2/user_info")

    fun isGamesUrl(url: String): Boolean =
        url.startsWith(gamesHome().toString())

    fun documentStartOrigins(): Set<String> = setOf(
        "https://$YANDEX_HOST",
    )

    fun logBridgeOrigins(): Set<String> = documentStartOrigins() + setOf(
        passportOrigin().toString(),
        "https://*.games.s3.yandex.net",
        "https://*.cdn.games.yandex.net",
        "https://*.gamecdn.yandex.net",
        "https://*.game-static.ru",
        "https://game-static.ru",
    )

    fun cookieOrigins(): List<String> = listOf(origin().toString(), passportOrigin().toString())

    private companion object {
        const val YANDEX_HOST = "yandex.ru"
    }
}

data class AppConfig(
    val yandex: YandexEndpoints,
    val http: HttpDefaults,
) {
    companion object {
        fun defaultForLocale(language: String = ""): AppConfig {
            return AppConfig(
                yandex = YandexEndpoints(),
                http = HttpDefaults(
                    userAgent = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36",
                ),
            )
        }
    }
}

private fun String.urlEncoded(): String =
    java.net.URLEncoder.encode(this, Charsets.UTF_8.name())
