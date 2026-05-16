package games.yandex.wrap.catalog

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

class CatalogHtmlParser(
    private val json: Json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true },
) {
    private val jsonParser = CatalogJsonParser()

    fun categoriesFromAppData(appData: String): List<GameCategory> {
        val parsed = runCatching { json.parseToJsonElement(appData) as? JsonObject }.getOrNull() ?: return emptyList()
        val arr = parsed["categoriesForTabs"] as? JsonArray ?: return emptyList()
        return arr.mapNotNull {
            val o = it as? JsonObject ?: return@mapNotNull null
            val name = o["name"]?.jsonPrimitive?.contentOrNull?.takeIf { s -> s.isNotEmpty() } ?: return@mapNotNull null
            val title = o["title"]?.jsonPrimitive?.contentOrNull?.takeIf { s -> s.isNotEmpty() } ?: return@mapNotNull null
            val count = o["gamesCount"]?.jsonPrimitive?.intOrNull ?: 0
            GameCategory(name = name, title = title, gamesCount = count)
        }
    }

    fun profileFromAppData(appData: String): UserProfile? {
        val parsed = runCatching { json.parseToJsonElement(appData) as? JsonObject }.getOrNull() ?: return null
        val userData = parsed["userData"] as? JsonObject ?: return null
        val uid = userData["uid"]?.jsonPrimitive?.contentOrNull.orEmpty()
        if (uid.isBlank()) return null
        val avatarsOrigin = userData["avatarsOrigin"]?.jsonPrimitive?.contentOrNull ?: "https://avatars.mds.yandex.net"
        val avatarId = userData["avatarId"]?.jsonPrimitive?.contentOrNull ?: "0/0-0"
        val avatarUrl = if (avatarId == "0/0-0") "" else "$avatarsOrigin/get-yapic/$avatarId/islands-300"
        return UserProfile(
            isAuthorized = true,
            displayName = userData["displayName"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            login = userData["login"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            avatarUrl = avatarUrl,
            hasYaPlus = userData["yaplusEnabled"]?.jsonPrimitive?.booleanOrNull == true,
        )
    }

    fun searchGamesFromAppData(appData: String): List<Game> {
        val parsed = runCatching { json.parseToJsonElement(appData) as? JsonObject }.getOrNull() ?: return emptyList()
        val searchObj = parsed["search"] as? JsonObject ?: return emptyList()
        val data = searchObj["data"] as? JsonArray ?: return emptyList()
        return jsonParser.parseFeedItems(data)
    }

    fun appDetailFromJsonLd(ldJson: String): AppDetail? {
        val parsed = runCatching { json.parseToJsonElement(ldJson) as? JsonObject }.getOrNull()
            ?: return null
        val graph = parsed["@graph"] as? JsonArray ?: JsonArray(emptyList())
        val gameNode = graph.firstOrNull { node ->
            val obj = node as? JsonObject ?: return@firstOrNull false
            val type = obj["@type"]?.jsonPrimitive?.contentOrNull
            type == "SoftwareApplication" || type == "VideoGame" || type == "MobileApplication"
        } as? JsonObject ?: return null

        val mainEntity = gameNode["mainEntityOfPage"] as? JsonObject
        val description = (mainEntity?.get("description") ?: gameNode["description"])
            ?.jsonPrimitive?.contentOrNull
            ?.let(::decodeHtmlEntities)
            ?.takeIf { it.isNotBlank() }
        val screenshots = (gameNode["screenshot"] as? JsonArray ?: JsonArray(emptyList()))
            .mapNotNull { item ->
                val s = item as? JsonObject ?: return@mapNotNull null
                s["url"]?.jsonPrimitive?.contentOrNull
            }
            .map { rewriteAvatarSize(it, "pjpg500x280") }
        val genres: List<String> = when (val g = gameNode["genre"]) {
            is JsonArray -> g.mapNotNull { it.jsonPrimitive.contentOrNull?.let(::decodeHtmlEntities) }
            is JsonObject -> emptyList()
            null -> emptyList()
            else -> g.jsonPrimitive.contentOrNull?.let(::decodeHtmlEntities)?.let(::listOf) ?: emptyList()
        }
        val languages: List<String> = when (val l = gameNode["inLanguage"]) {
            is JsonArray -> l.mapNotNull { it.jsonPrimitive.contentOrNull }
            null -> emptyList()
            else -> l.jsonPrimitive.contentOrNull?.let(::listOf) ?: emptyList()
        }
        val author = (gameNode["author"] as? JsonObject)?.get("name")?.jsonPrimitive?.contentOrNull
            ?.let(::decodeHtmlEntities)
            ?.takeIf { it.isNotBlank() }
        return AppDetail(
            description = description,
            screenshots = screenshots,
            datePublished = gameNode["datePublished"]?.jsonPrimitive?.contentOrNull,
            genres = genres,
            languages = languages,
            author = author,
        )
    }

    fun extractJsonLd(html: String): String? {
        val markers = listOf("type=\"application/ld+json\"", "type='application/ld+json'")
        for (marker in markers) {
            val markerIdx = html.indexOf(marker)
            if (markerIdx < 0) continue
            val openTag = html.indexOf('>', markerIdx)
            if (openTag < 0) continue
            val closeTag = html.indexOf("</script>", openTag)
            if (closeTag < 0) continue
            return html.substring(openTag + 1, closeTag).trim()
        }
        return null
    }

    fun extractAppData(html: String): String? {
        val marker = "id=\"__appData__\""
        val markerIdx = html.indexOf(marker)
        if (markerIdx < 0) return null
        val openTag = html.indexOf('>', markerIdx)
        if (openTag < 0) return null
        val closeTag = html.indexOf("</script>", openTag)
        if (closeTag < 0) return null
        return html.substring(openTag + 1, closeTag)
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
}
