package games.yandex.wrap.catalog

import games.yandex.wrap.catalog.models.AppDetail
import games.yandex.wrap.catalog.models.FeedBlock
import games.yandex.wrap.catalog.models.FeedPage
import games.yandex.wrap.catalog.models.FeedWithBlocks
import games.yandex.wrap.catalog.models.Game
import games.yandex.wrap.catalog.models.GameCategory
import games.yandex.wrap.catalog.models.UserProfile
import games.yandex.wrap.util.dedupeBy
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.floatOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

interface CatalogParser {
    fun feedWithBlocks(response: JsonObject): FeedWithBlocks
    fun feedPage(response: JsonObject): FeedPage
    fun similarGames(response: JsonObject): List<Game>
    fun parseFeedItems(blocks: JsonArray): List<Game>
    fun appDetail(response: JsonObject): AppDetail?
    fun categoriesFromTags(response: JsonObject): List<GameCategory>
    fun profile(response: JsonObject): UserProfile?
}

class YandexCatalogJsonParser(
    @Suppress("unused") private val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    },
) : CatalogParser {
    override fun feedWithBlocks(response: JsonObject): FeedWithBlocks {
        val feedArr = response["feed"] as? JsonArray ?: JsonArray(emptyList())
        val blocks = feedArr.mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val type = obj["type"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val size = obj["size"]?.jsonPrimitive?.contentOrNull
            val title = obj["title"]?.jsonPrimitive?.contentOrNull.orEmpty()
            val itemsArr = obj["items"] as? JsonArray ?: JsonArray(emptyList())
            val items = itemsArr.mapNotNull { (it as? JsonObject)?.let(::itemToGame) }
            if (items.isEmpty()) null else FeedBlock(type, size, title, items)
        }
        val flat = blocks.flatMap { it.items }.dedupeBy { it.appId }
        val pageInfo = response["pageInfo"] as? JsonObject
        val nextPageId = pageInfo?.get("nextPageId")?.jsonPrimitive?.contentOrNull
        val hasNext = pageInfo?.get("hasNextPage")?.jsonPrimitive?.booleanOrNull ?: (nextPageId != null)
        val recentArr = response["recentGames"] as? JsonArray ?: JsonArray(emptyList())
        val recentGames = recentArr.mapNotNull { (it as? JsonObject)?.let(::itemToGame) }
        return FeedWithBlocks(
            blocks = blocks,
            flatGames = flat,
            recentGames = recentGames,
            genres = emptyList(),
            nextPageId = nextPageId,
            hasNext = hasNext,
        )
    }

    override fun feedPage(response: JsonObject): FeedPage {
        val pageInfo = response["pageInfo"] as? JsonObject
        val nextPageId = pageInfo?.get("nextPageId")?.jsonPrimitive?.contentOrNull
        val hasNext = pageInfo?.get("hasNextPage")?.jsonPrimitive?.booleanOrNull ?: (nextPageId != null)
        return FeedPage(
            games = parseFeedItems(response["feed"] as? JsonArray ?: JsonArray(emptyList())),
            nextPageId = nextPageId,
            hasNext = hasNext,
        )
    }

    override fun similarGames(response: JsonObject): List<Game> {
        val games = response["games"] as? JsonArray
        if (games != null) {
            return games.mapNotNull { (it as? JsonObject)?.let(::itemToGame) }.dedupeBy { it.appId }
        }
        return parseFeedItems(response["feed"] as? JsonArray ?: JsonArray(emptyList()))
    }

    override fun parseFeedItems(blocks: JsonArray): List<Game> {
        val out = mutableListOf<Game>()
        for (block in blocks) {
            val obj = block as? JsonObject ?: continue
            val items = obj["items"]?.jsonArray ?: continue
            for (item in items) {
                val itemObj = item as? JsonObject ?: continue
                val game = itemToGame(itemObj) ?: continue
                out.add(game)
            }
        }
        return out.dedupeBy { it.appId }
    }

    override fun appDetail(response: JsonObject): AppDetail? {
        val game = response["game"] as? JsonObject ?: return null
        val description = game["description"]?.jsonPrimitive?.contentOrNull
            ?.let(::decodeHtmlEntities)
            ?.takeIf { it.isNotBlank() }
        val screenshots = screenshots(game)
        val genres = (game["categoriesNames"] as? JsonArray)
            ?.mapNotNull { it.jsonPrimitive.contentOrNull?.let(::decodeHtmlEntities) }
            ?: emptyList()
        val languages = (game["inLanguage"] as? JsonArray)
            ?.mapNotNull { it.jsonPrimitive.contentOrNull }
            ?: game["inLanguage"]?.jsonPrimitive?.contentOrNull?.let(::listOf)
            ?: emptyList()
        val developer = (game["developer"] as? JsonObject)
            ?.get("name")?.jsonPrimitive?.contentOrNull
            ?.let(::decodeHtmlEntities)
            ?.takeIf { it.isNotBlank() }
        return AppDetail(
            description = description,
            screenshots = screenshots,
            datePublished = game["datePublished"]?.jsonPrimitive?.contentOrNull
                ?: game["releaseDate"]?.jsonPrimitive?.contentOrNull,
            genres = genres,
            languages = languages,
            author = developer,
        )
    }

    override fun categoriesFromTags(response: JsonObject): List<GameCategory> {
        val tags = response["tags"] as? JsonArray ?: return emptyList()
        return tags.mapNotNull { item ->
            val tag = item as? JsonObject ?: return@mapNotNull null
            val slug = tag["slug"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
                ?: return@mapNotNull null
            val title = tag["title"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
                ?: return@mapNotNull null
            val info = tag["info"] as? JsonObject
            GameCategory(
                name = slug,
                title = title,
                gamesCount = info?.get("games_count")?.jsonPrimitive?.intOrNull ?: 0,
            )
        }
    }

    override fun profile(response: JsonObject): UserProfile? {
        val userData = (response["userData"] as? JsonObject)
            ?: (response["user"] as? JsonObject)
            ?: response
        val uid = userData["uid"]?.jsonPrimitive?.contentOrNull
            ?: userData["id"]?.jsonPrimitive?.contentOrNull
            ?: userData["passportUid"]?.jsonPrimitive?.contentOrNull
            ?: ""
        if (uid.isBlank()) return null
        val avatarsOrigin = userData["avatarsOrigin"]?.jsonPrimitive?.contentOrNull
            ?: "https://avatars.mds.yandex.net"
        val avatarId = userData["avatarId"]?.jsonPrimitive?.contentOrNull ?: "0/0-0"
        val avatarUrl = userData["avatarUrl"]?.jsonPrimitive?.contentOrNull
            ?: if (avatarId == "0/0-0") "" else "$avatarsOrigin/get-yapic/$avatarId/islands-300"
        return UserProfile(
            isAuthorized = true,
            displayName = userData["displayName"]?.jsonPrimitive?.contentOrNull
                ?: userData["name"]?.jsonPrimitive?.contentOrNull
                ?: "",
            login = userData["login"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            avatarUrl = avatarUrl,
            hasYaPlus = userData["yaplusEnabled"]?.jsonPrimitive?.booleanOrNull == true ||
                userData["hasYaPlus"]?.jsonPrimitive?.booleanOrNull == true,
        )
    }

    private fun itemToGame(item: JsonObject): Game? {
        val appId = item["appID"]?.jsonPrimitive?.longOrNull ?: return null
        val title = item["title"]?.jsonPrimitive?.contentOrNull ?: return null
        val rating = item["rating"]?.jsonPrimitive?.floatOrNull ?: 0f
        val ratingCount = item["ratingCount"]?.jsonPrimitive?.intOrNull ?: 0
        val media = item["media"] as? JsonObject
        val coverObj = media?.get("cover") as? JsonObject
        val iconObj = media?.get("icon") as? JsonObject
        val coverPrefix = coverObj?.get("prefix-url")?.jsonPrimitive?.contentOrNull
        val iconPrefix = iconObj?.get("prefix-url")?.jsonPrimitive?.contentOrNull
        val mainColor = coverObj?.get("mainColor")?.jsonPrimitive?.contentOrNull
        val iconMainColor = iconObj?.get("mainColor")?.jsonPrimitive?.contentOrNull
        val videoUrl = (media?.get("videos") as? JsonArray)
            ?.firstOrNull()
            ?.let { it as? JsonObject }
            ?.get("mp4StreamUrl")?.jsonPrimitive?.contentOrNull
        val categories = (item["categoriesNames"] as? JsonElement)
            ?.let { it as? JsonArray }
            ?.mapNotNull { it.jsonPrimitive.contentOrNull }
            ?: emptyList()
        val developer = (item["developer"] as? JsonObject)
            ?.get("name")?.jsonPrimitive?.contentOrNull
            ?: ""
        val ageRating = (item["features"] as? JsonObject)
            ?.get("age_rating")?.jsonPrimitive?.contentOrNull
            ?.takeIf { it.isNotBlank() }
        return Game(
            appId = appId,
            title = title,
            rating = rating,
            ratingCount = ratingCount,
            coverUrl = coverPrefix?.let { it + COVER_SIZE } ?: "",
            iconUrl = iconPrefix?.let { it + ICON_SIZE } ?: coverPrefix?.let { it + ICON_SIZE } ?: "",
            categories = categories,
            developer = developer,
            mainColor = mainColor,
            iconMainColor = iconMainColor,
            videoUrl = videoUrl,
            coverPrefixUrl = coverPrefix,
            ageRating = ageRating,
        )
    }

    private fun screenshots(game: JsonObject): List<String> {
        val media = game["media"] as? JsonObject ?: return emptyList()
        val screenshots = media["screenshots"] ?: return emptyList()
        return when (screenshots) {
            is JsonArray -> screenshots.mapNotNull(::screenshotUrl)
            is JsonObject -> screenshots.values.flatMap { value ->
                (value as? JsonArray)?.mapNotNull(::screenshotUrl) ?: emptyList()
            }
            else -> emptyList()
        }.dedupeBy { it }
    }

    private fun screenshotUrl(item: JsonElement): String? {
        val obj = item as? JsonObject ?: return null
        val prefix = obj["prefix-url"]?.jsonPrimitive?.contentOrNull
        if (!prefix.isNullOrBlank()) return prefix + DETAIL_SCREENSHOT_SIZE
        return obj["url"]?.jsonPrimitive?.contentOrNull?.let { rewriteAvatarSize(it, DETAIL_SCREENSHOT_SIZE) }
    }

    private fun rewriteAvatarSize(url: String, newSize: String): String {
        val lastSlash = url.lastIndexOf('/')
        if (lastSlash <= 0) return url
        return url.substring(0, lastSlash + 1) + newSize
    }

    private fun decodeHtmlEntities(s: String): String =
        s.replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")

    private companion object {
        const val COVER_SIZE = "pjpg250x140"
        const val ICON_SIZE = "pjpg256x256"
        const val DETAIL_SCREENSHOT_SIZE = "pjpg500x280"
    }
}
