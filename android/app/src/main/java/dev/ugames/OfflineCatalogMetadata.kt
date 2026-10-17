package dev.ugames

import java.net.URI
import org.json.JSONObject

/** Catalogue packets have a stronger trust boundary than reports from embedded game frames. */
data class OfflineCatalogMetadata(
    val gameId: String,
    val url: String,
    val title: String,
    val cover: String?
) {
    internal fun json() = JSONObject().put("url", url).put("title", title).put("cover", cover ?: "")
    internal fun isValid() =
        gameId.matches(Regex("[0-9]{1,32}")) && catalogId(url) == gameId && title.isNotBlank() &&
            title.length <= 200 &&
            (cover == null || isCoverUrl(cover))

    companion object {
        private val hosts = setOf("yandex.ru", "www.yandex.ru", "yandex.com", "www.yandex.com")
        private val coverHosts =
            setOf("avatars.mds.yandex.net", "avatars.mds.yandex.ru", "avatars.mds.yandex.com")

        fun parse(
            message: String,
            sourceOrigin: String,
            pageUrl: String?,
            mainFrame: Boolean
        ): OfflineCatalogMetadata? {
            if (!mainFrame || message.length > 16384 || pageUrl == null) return null
            val source = OfflineResourcePolicy.normalize(sourceOrigin) ?: return null
            val page = OfflineResourcePolicy.normalize(pageUrl) ?: return null
            if (URI(source).host !in hosts ||
                OfflineResourcePolicy.origin(page) != OfflineResourcePolicy.origin(source) ||
                !isCatalogContext(page)
            ) {
                return null
            }
            return try {
                val json = JSONObject(message)
                if (json.optInt("version") != 1 || json.optString("type") != "catalog") return null
                val cover = json.optString("cover").takeIf(::isCoverUrl)
                OfflineCatalogMetadata(
                    json.getString("gameId"),
                    json.getString("url"),
                    json.getString("title").trim().take(200),
                    cover
                ).takeIf {
                    it.isValid()
                }
            } catch (_: Exception) {
                null
            }
        }

        fun gameId(entry: String): String? = OfflineResourcePolicy.normalize(entry)?.let {
            Regex("^app-([0-9]{1,32})\\.").find(URI(it).host)?.groupValues?.get(1)
        }

        fun isCatalogContext(value: String): Boolean = OfflineResourcePolicy.normalize(value)?.let {
            val uri = URI(it)
            uri.host in hosts && (uri.path == "/games" || uri.path.startsWith("/games/"))
        } ?: false

        fun isCoverUrl(value: String): Boolean = OfflineResourcePolicy.normalize(value)?.let {
            val uri = URI(it)
            uri.host in coverHosts &&
                (uri.path.startsWith("/get-games/") || uri.path.startsWith("/get-games-avatars/"))
        } ?: false

        private fun catalogId(value: String): String? =
            OfflineResourcePolicy.normalize(value)?.let {
                val uri = URI(it)
                if (uri.host !in
                    hosts
                ) {
                    null
                } else {
                    Regex("^/games/app/([0-9]{1,32})/?$").matchEntire(uri.path)?.groupValues?.get(1)
                }
            }
    }
}
