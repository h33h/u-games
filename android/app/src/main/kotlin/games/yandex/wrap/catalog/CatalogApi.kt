package games.yandex.wrap.catalog

import android.webkit.CookieManager
import games.yandex.wrap.diagnostics.LogStore
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.floatOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.Locale
import java.util.concurrent.TimeUnit

data class FeedPage(
    val games: List<Game>,
    val nextPageId: String?,
    val hasNext: Boolean,
)

data class UserProfile(
    val isAuthorized: Boolean,
    val displayName: String,
    val login: String,
    val avatarUrl: String,
    val hasYaPlus: Boolean,
)

class CatalogApi(private val httpClient: HttpClient) {

    private val lenientJson = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }

    suspend fun firstFeedPage(
        gamesPerPage: Int = 24,
        lang: String = "en",
        clientWidth: Int = 412,
        clientHeight: Int = 915,
    ): FeedPage = fetchFeed(pageId = null, gamesPerPage = gamesPerPage, lang = lang, clientWidth = clientWidth, clientHeight = clientHeight)

    suspend fun nextFeedPage(
        pageId: String,
        gamesPerPage: Int = 24,
        lang: String = "en",
        clientWidth: Int = 412,
        clientHeight: Int = 915,
    ): FeedPage = fetchFeed(pageId = pageId, gamesPerPage = gamesPerPage, lang = lang, clientWidth = clientWidth, clientHeight = clientHeight)

    private suspend fun fetchFeed(
        pageId: String?,
        gamesPerPage: Int,
        lang: String,
        clientWidth: Int,
        clientHeight: Int,
    ): FeedPage {
        val response: JsonObject = httpClient.get(FEED_URL) {
            parameter("with_promos", "true")
            parameter("lang", lang)
            parameter("games_count", gamesPerPage.toString())
            parameter("categorized_size", "5")
            parameter("with_recent_games", "true")
            parameter("platform", "android_other")
            parameter("client_width", clientWidth.toString())
            parameter("client_height", clientHeight.toString())
            if (pageId != null) parameter("page_id", pageId)
            mobileHeaders()
        }.body()

        val games = parseFeedItems(response["feed"] as? JsonArray ?: JsonArray(emptyList()))
        val pageInfo = response["pageInfo"] as? JsonObject
        val nextPageId = pageInfo?.get("nextPageId")?.jsonPrimitive?.contentOrNull
        val hasNext = pageInfo?.get("hasNextPage")?.jsonPrimitive?.booleanOrNull ?: (nextPageId != null)
        return FeedPage(games = games, nextPageId = nextPageId, hasNext = hasNext)
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
        return parseFeedItems(response["feed"] as? JsonArray ?: JsonArray(emptyList()))
    }

    /**
     * Yandex doesn't expose a JSON search endpoint — search is server-rendered.
     * Pull the HTML, extract the `<script id="__appData__">` JSON, and read
     * `search.data[].items[]`.
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
        return parseFeedItems(data)
    }

    /**
     * Pull `__appData__.userData` from the catalog page HTML to detect login
     * state and obtain avatar / display name.
     *
     * Locale-aware: Russian-locale devices fetch yandex.ru/games/ (the same
     * realm AuthScreen authenticated against) so the SSR sees the matching
     * Session_id. PWL passport sets Session_id only on `.yandex.com`; Russian
     * users get geo-redirected to `yandex.ru`, and CookieManager only attaches
     * cookies for the request's scheme+host pair — `.yandex.com` cookies would
     * NOT travel onto a `.yandex.ru` redirect, leaving the SSR anonymous. So
     * we bypass Ktor's HttpCookies plugin and ship a manually-merged Cookie
     * header containing every yandex.* cookie. Mirrors iOS
     * CatalogService.fetchProfile + ProfileFetchRedirectDelegate.
     */
    suspend fun userProfile(lang: String = "en"): UserProfile = withContext(Dispatchers.IO) {
        val host = preferredYandexHost()
        val effectiveLang = if (host == "yandex.ru") "ru" else lang
        val url = "https://$host/games/?lang=$effectiveLang"
        val cookieHeader = buildMergedYandexCookieHeader()
        LogStore.log(
            "profile",
            "fetch begin url=$url cookieHeaderLen=${cookieHeader.length}",
        )
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", MOBILE_UA)
            .header("Accept", "text/html")
            .header("Accept-Language", "$effectiveLang,en;q=0.9")
            .apply { if (cookieHeader.isNotEmpty()) header("Cookie", cookieHeader) }
            .get()
            .build()
        val response = try {
            profileHttp.newCall(request).execute()
        } catch (t: Throwable) {
            LogStore.log("profile", "fetch FAILED: ${t.message}")
            return@withContext ANON
        }
        val html = response.use { resp ->
            LogStore.log(
                "profile",
                "fetch http status=${resp.code} finalUrl=${resp.request.url}",
            )
            resp.body?.string().orEmpty()
        }
        val appData = extractAppData(html)
        if (appData == null) {
            LogStore.log("profile", "NO __appData__ found (htmlLen=${html.length})")
            return@withContext ANON
        }
        val parsed = lenientJson.parseToJsonElement(appData) as? JsonObject
        if (parsed == null) {
            LogStore.log("profile", "appData not a JSON object")
            return@withContext ANON
        }
        val userData = parsed["userData"] as? JsonObject
        if (userData == null) {
            LogStore.log("profile", "no userData key")
            return@withContext ANON
        }
        val uid = userData["uid"]?.jsonPrimitive?.contentOrNull.orEmpty()
        val login = userData["login"]?.jsonPrimitive?.contentOrNull.orEmpty()
        LogStore.log(
            "profile",
            "userData uid=${uid.ifEmpty { "<empty>" }} login=$login",
        )
        if (uid.isBlank()) return@withContext ANON
        val avatarsOrigin = userData["avatarsOrigin"]?.jsonPrimitive?.contentOrNull ?: "https://avatars.mds.yandex.net"
        val avatarId = userData["avatarId"]?.jsonPrimitive?.contentOrNull ?: "0/0-0"
        val avatarUrl = if (avatarId == "0/0-0") "" else "$avatarsOrigin/get-yapic/$avatarId/islands-300"
        UserProfile(
            isAuthorized = true,
            displayName = userData["displayName"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            login = login,
            avatarUrl = avatarUrl,
            hasYaPlus = userData["yaplusEnabled"]?.jsonPrimitive?.booleanOrNull == true,
        )
    }

    /**
     * Reads cookies for both yandex.com and yandex.ru from the system
     * CookieManager and merges them into a single Cookie header with last-write
     * dedupe by name (cookies for both TLDs often share names like Session_id;
     * the freshest value is what passport just set). Returns "" when no
     * yandex.* cookies are available — the caller skips the Cookie header.
     */
    private fun buildMergedYandexCookieHeader(): String {
        val cm = CookieManager.getInstance()
        val merged = LinkedHashMap<String, String>()
        for (host in COOKIE_DONOR_HOSTS) {
            val raw = cm.getCookie(host).orEmpty()
            if (raw.isEmpty()) continue
            for (pair in raw.split(';')) {
                val trimmed = pair.trim()
                val idx = trimmed.indexOf('=')
                if (idx <= 0) continue
                val name = trimmed.substring(0, idx)
                val value = trimmed.substring(idx + 1)
                merged[name] = value
            }
        }
        return merged.entries.joinToString("; ") { "${it.key}=${it.value}" }
    }

    /**
     * Locale-aware host pick: Russian users hit yandex.ru so the SSR runs the
     * same realm passport authenticated against (passport.yandex.ru issues
     * Session_id only on `.yandex.ru`). Mirrors AuthScreen's preferredHost.
     */
    private fun preferredYandexHost(): String =
        if (Locale.getDefault().language.lowercase().startsWith("ru")) "yandex.ru" else "yandex.com"

    /**
     * Bare OkHttp client used only for profile fetch. Has NO CookieJar so the
     * manually-merged Cookie header is preserved across the .com→.ru
     * geo-redirect (OkHttp's default redirect handling re-sends the original
     * request headers, including our Cookie). Mirrors iOS
     * `httpShouldHandleCookies = false`.
     */
    private val profileHttp: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
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

    private fun parseFeedItems(blocks: JsonArray): List<Game> {
        val seen = mutableSetOf<Long>()
        val out = mutableListOf<Game>()
        for (block in blocks) {
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

    private fun io.ktor.client.request.HttpRequestBuilder.mobileHeaders() {
        header(HttpHeaders.UserAgent, MOBILE_UA)
        header(HttpHeaders.Accept, "application/json,text/html;q=0.9")
        header(HttpHeaders.AcceptLanguage, "en-US,en;q=0.9")
    }

    private companion object {
        const val FEED_URL = "https://yandex.com/games/api/catalogue/v2/feed/"
        const val SIMILAR_URL = "https://yandex.com/games/api/catalogue/v2/similar_games/"
        const val SEARCH_URL = "https://yandex.com/games/search"
        const val CATALOG_URL = "https://yandex.com/games/"
        const val MOBILE_UA = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36"
        const val COVER_SIZE = "pjpg250x140"
        const val ICON_SIZE = "pjpg256x256"
        val ANON = UserProfile(false, "", "", "", false)
        // Hosts whose cookie jars contribute to the profile-fetch Cookie
        // header. Order matters: later entries override earlier ones (last-
        // write wins) so the freshest Session_id from the user's authenticated
        // realm is what the SSR sees.
        val COOKIE_DONOR_HOSTS = listOf(
            "https://yandex.com",
            "https://yandex.ru",
            "https://passport.yandex.com",
            "https://passport.yandex.ru",
        )
    }
}
