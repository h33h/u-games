package games.yandex.wrap.catalog

import games.yandex.wrap.util.dedupeBy
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

class CatalogJsonParser {
    fun feedWithBlocks(response: JsonObject): FeedWithBlocks {
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

    fun feedPage(response: JsonObject): FeedPage {
        val pageInfo = response["pageInfo"] as? JsonObject
        val nextPageId = pageInfo?.get("nextPageId")?.jsonPrimitive?.contentOrNull
        val hasNext = pageInfo?.get("hasNextPage")?.jsonPrimitive?.booleanOrNull ?: (nextPageId != null)
        return FeedPage(
            games = parseFeedItems(response["feed"] as? JsonArray ?: JsonArray(emptyList())),
            nextPageId = nextPageId,
            hasNext = hasNext,
        )
    }

    fun similarGames(response: JsonObject): List<Game> {
        val games = response["games"] as? JsonArray
        if (games != null) {
            return games.mapNotNull { (it as? JsonObject)?.let(::itemToGame) }.dedupeBy { it.appId }
        }
        return parseFeedItems(response["feed"] as? JsonArray ?: JsonArray(emptyList()))
    }

    fun parseFeedItems(blocks: JsonArray): List<Game> {
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

    private companion object {
        const val COVER_SIZE = "pjpg250x140"
        const val ICON_SIZE = "pjpg256x256"
    }
}
