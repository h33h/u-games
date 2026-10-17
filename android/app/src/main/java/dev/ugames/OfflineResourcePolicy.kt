package dev.ugames

import java.net.URI
import java.util.Locale
import org.json.JSONObject

/** URL keys keep queries intact: two revisions of the same asset are different files. */
object OfflineResourcePolicy {
    const val MAX_METADATA_BYTES = 2 * 1024 * 1024
    const val MAX_RESOURCES = 4096
    private val staticExtensions = setOf(
        "js", "mjs", "cjs", "css", "json", "wasm", "png", "jpg", "jpeg", "gif", "webp",
        "avif", "svg", "ico", "woff", "woff2", "ttf", "otf", "mp3", "wav", "ogg", "m4a",
        "mp4", "webm", "bin", "data", "pck", "bundle", "unityweb", "gz", "br", "txt",
        "xml", "atlas", "ktx", "ktx2", "basis", "mem", "dat", "fnt", "glb", "gltf"
    )
    private val servicePath =
        Regex(
            "/(api|auth|oauth|login|passport|analytics|metrics|telemetry)(/|$)",
            RegexOption.IGNORE_CASE
        )

    fun normalize(value: String): String? = try {
        val uri = URI(value).normalize()
        val host = uri.host?.lowercase(Locale.ROOT)
        if (!uri.scheme.equals("https", true) || host.isNullOrBlank() || uri.userInfo != null ||
            uri.port !in listOf(-1, 443) || value.length > 16384
        ) {
            null
        } else {
            "https://$host${uri.rawPath.takeUnless { it.isNullOrEmpty() } ?: "/"}" +
                (uri.rawQuery?.let { "?$it" } ?: "")
        }
    } catch (_: Exception) {
        null
    }

    fun origin(value: String): String? = normalize(value)?.let { "https://${URI(it).host}" }

    fun navigationUrl(value: String): String? = normalize(value)?.let { normalized ->
        normalized + (URI(value).rawFragment?.let { "#$it" } ?: "")
    }

    fun isGameUrl(value: String): Boolean = normalize(value)?.let {
        val host = URI(it).host
        host.endsWith(".games.yandex.net") || host.endsWith(".games.s3.yandex.net")
    } ?: false

    fun isSdk(value: String): Boolean = normalize(value)?.let {
        val path = URI(it).path.lowercase(Locale.ROOT)
        path == "/sdk.js" || path == "/sdk" || path.startsWith("/sdk/")
    } ?: false

    fun canSave(entryUrl: String, value: String): Boolean {
        val normalized = normalize(value) ?: return false
        val uri = URI(normalized)
        val host = uri.host
        val path = uri.path.orEmpty()
        if (isSdk(normalized) || servicePath.containsMatchIn(path) ||
            host in setOf("yandex.ru", "www.yandex.ru", "yandex.com", "www.yandex.com", "ya.ru") ||
            host.split('.').any { it in setOf("passport", "api", "auth", "accounts", "sso") }
        ) {
            return false
        }
        if (origin(entryUrl) == origin(normalized)) return true
        return path.substringAfterLast('.', "").lowercase(Locale.ROOT) in staticExtensions
    }
}

data class OfflineCaptureReport(
    val entryUrl: String,
    val title: String,
    val resources: List<String>,
    val storage: Map<String, String>,
    val environment: String,
    val ready: Boolean
) {
    companion object {
        fun parse(
            message: String,
            sourceOrigin: String,
            pageTitle: String?
        ): OfflineCaptureReport? {
            if (message.length > OfflineResourcePolicy.MAX_METADATA_BYTES ||
                message.toByteArray(Charsets.UTF_8).size > OfflineResourcePolicy.MAX_METADATA_BYTES
            ) {
                return null
            }
            return try {
                val json = JSONObject(message)
                val entry =
                    OfflineResourcePolicy.navigationUrl(json.getString("url")) ?: return null
                if (json.optInt("version") != 1 || !OfflineResourcePolicy.isGameUrl(entry) ||
                    OfflineResourcePolicy.origin(entry) !=
                    OfflineResourcePolicy.origin(sourceOrigin)
                ) {
                    return null
                }
                val urls = json.getJSONArray("resources")
                if (urls.length() > OfflineResourcePolicy.MAX_RESOURCES) return null
                val capturedTitle = json.optString("title").trim().take(200)
                val generic = capturedTitle.isBlank() || capturedTitle.lowercase(Locale.ROOT) in
                    setOf(
                        "game",
                        "new project",
                        "construct 3",
                        "untitled",
                        "untitled game",
                        "unity webgl player",
                        "yandex games",
                        "яндекс игры",
                        "index.html"
                    ) ||
                    capturedTitle.startsWith("Unity WebGL Player |")
                val title = (if (generic) pageTitle?.trim()?.take(200) else capturedTitle)
                    .takeUnless { it.isNullOrBlank() } ?: "Сохранённая игра"
                val storage = json.optJSONObject("storage") ?: JSONObject()
                OfflineCaptureReport(
                    entry,
                    title,
                    (0 until urls.length()).mapNotNull {
                        OfflineResourcePolicy.normalize(urls.optString(it))
                    }.distinct(),
                    storage.keys().asSequence().filter { storage.opt(it) is String }
                        .associateWith { storage.getString(it) },
                    (json.optJSONObject("environment") ?: JSONObject()).toString(),
                    json.optBoolean("ready", false)
                )
            } catch (_: Exception) {
                null
            }
        }
    }
}
