package games.yandex.wrap.catalog

import android.util.Base64
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.floatOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

class CatalogApi(private val httpClient: HttpClient) {

    private val lenientJson = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }

    suspend fun feed(
        skip: Int = 0,
        gamesPerPage: Int = 24,
        lang: String = "en",
        clientWidth: Int = 412,
        clientHeight: Int = 915,
    ): List<Game> {
        val response: JsonObject = httpClient.get(FEED_URL) {
            parameter("with_promos", "true")
            parameter("lang", lang)
            parameter("games_count", gamesPerPage.toString())
            parameter("categorized_size", "5")
            parameter("with_recent_games", "true")
            parameter("platform", "android_other")
            parameter("client_width", clientWidth.toString())
            parameter("client_height", clientHeight.toString())
            if (skip > 0) parameter("page_id", encodeSkip(skip))
            mobileHeaders()
        }.body()
        return parseFeed(response)
    }

    suspend fun similar(appId: Long, lang: String = "en"): List<Game> {
        val response: JsonObject = httpClient.get(SIMILAR_URL) {
            parameter("app_id", appId.toString())
            parameter("games_count", "16")
            parameter("int", "true")
            parameter("lang", lang)
            parameter("page_type", "game")
            parameter("platform", "android_other")
            parameter("standalone", "false")
            mobileHeaders()
        }.body()
        return parseFeed(response)
    }

    /**
     * Search via the SSR HTML page — Yandex doesn't expose a JSON endpoint.
     * The page embeds a `<script id="__appData__">` element containing all
     * data, including `search.data[].items[]`.
     */
    suspend fun search(query: String, lang: String = "en"): List<Game> {
        if (query.isBlank()) return emptyList()
        val response: HttpResponse = httpClient.get(SEARCH_URL) {
            parameter("query", query)
            parameter("lang", lang)
            mobileHeaders()
        }
        val html = response.bodyAsText()
        val appData = extractAppData(html) ?: return emptyList()
        val parsed = lenientJson.parseToJsonElement(appData) as? JsonObject ?: return emptyList()
        val searchObj = parsed["search"] as? JsonObject ?: return emptyList()
        val data = searchObj["data"] as? JsonArray ?: return emptyList()
        val seen = mutableSetOf<Long>()
        val out = mutableListOf<Game>()
        for (block in data) {
            val obj = block as? JsonObject ?: continue
            val items = obj["items"] as? JsonArray ?: continue
            for (item in items) {
                val itemObj = item as? JsonObject ?: continue
                val game = itemToGame(itemObj) ?: continue
                if (seen.add(game.appId)) out.add(game)
            }
        }
        return out
    }

    private fun extractAppData(html: String): String? {
        val marker = "id=\"__appData__\""
        val markerIdx = html.indexOf(marker)
        if (markerIdx < 0) return null
        val openTag = html.indexOf('>', markerIdx)
        if (openTag < 0) return null
        val closeTag = html.indexOf("</script>", openTag)
        if (closeTag < 0) return null
        return html.substring(openTag + 1, closeTag)
    }

    private fun parseFeed(json: JsonObject): List<Game> {
        val seen = mutableSetOf<Long>()
        val out = mutableListOf<Game>()
        val feed = json["feed"]?.jsonArray ?: return emptyList()
        for (block in feed) {
            val obj = block as? JsonObject ?: continue
            val items = obj["items"]?.jsonArray ?: continue
            for (item in items) {
                val itemObj = item as? JsonObject ?: continue
                val game = itemToGame(itemObj) ?: continue
                if (seen.add(game.appId)) out.add(game)
            }
        }
        return out
    }

    private fun itemToGame(item: JsonObject): Game? {
        val appId = item["appID"]?.jsonPrimitive?.longOrNull ?: return null
        val title = item["title"]?.jsonPrimitive?.contentOrNull ?: return null
        val rating = item["rating"]?.jsonPrimitive?.floatOrNull ?: 0f
        val ratingCount = item["ratingCount"]?.jsonPrimitive?.intOrNull ?: 0
        val media = item["media"] as? JsonObject
        val coverPrefix = media?.get("cover")?.jsonObject?.get("prefix-url")?.jsonPrimitive?.contentOrNull
        val iconPrefix = media?.get("icon")?.jsonObject?.get("prefix-url")?.jsonPrimitive?.contentOrNull
        val categories = (item["categoriesNames"] as? JsonElement)
            ?.let { it as? JsonArray }
            ?.mapNotNull { it.jsonPrimitive.contentOrNull }
            ?: emptyList()
        val developer = (item["developer"] as? JsonObject)
            ?.get("name")?.jsonPrimitive?.contentOrNull
            ?: ""
        return Game(
            appId = appId,
            title = title,
            rating = rating,
            ratingCount = ratingCount,
            coverUrl = coverPrefix?.let { it + COVER_SIZE } ?: "",
            iconUrl = iconPrefix?.let { it + ICON_SIZE } ?: coverPrefix?.let { it + ICON_SIZE } ?: "",
            categories = categories,
            developer = developer,
        )
    }

    private fun encodeSkip(skip: Int): String =
        Base64.encodeToString("gamesSkip=$skip".toByteArray(Charsets.UTF_8), Base64.NO_WRAP or Base64.NO_PADDING)

    private fun io.ktor.client.request.HttpRequestBuilder.mobileHeaders() {
        header(HttpHeaders.UserAgent, MOBILE_UA)
        header(HttpHeaders.Accept, "application/json,text/html;q=0.9")
        header(HttpHeaders.AcceptLanguage, "en-US,en;q=0.9")
    }

    private companion object {
        const val FEED_URL = "https://yandex.com/games/api/catalogue/v2/feed/"
        const val SIMILAR_URL = "https://yandex.com/games/api/catalogue/v2/similar_games/"
        const val SEARCH_URL = "https://yandex.com/games/search"
        const val MOBILE_UA = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36"
        const val COVER_SIZE = "pjpg250x140"
        const val ICON_SIZE = "pjpg256x256"
    }
}
