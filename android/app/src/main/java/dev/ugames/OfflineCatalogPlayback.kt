package dev.ugames

import android.app.Activity
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import org.json.JSONArray
import org.json.JSONObject

/** This catalogue has the same HTTPS address as the portal and no network escape hatch. */
class OfflineCatalogPlayback(activity: Activity, val games: List<SavedOfflineGame>) {
    private val html = activity.assets.open("ugames/offline-catalog.html").use { it.readBytes() }
    private val covers = games.mapNotNull { game ->
        game.coverLocalUrl?.let { it to game.cover!! }
    }.toMap()

    fun configurationScript(): String =
        "window.__UGamesCachedCatalog=" + JSONObject().put("version", 1)
            .put(
                "games",
                JSONArray().also { list ->
                    games.forEach { game ->
                        list.put(
                            JSONObject().put(
                                "url",
                                game.entryUrl
                            ).put("title", game.title).also { record ->
                                game.coverLocalUrl?.let { record.put("cover", it) }
                            }
                        )
                    }
                }
            ).toString().replace("<", "\\u003c") + ";"

    fun allowsDocument(url: String) =
        OfflineResourcePolicy.normalize(url) == BOOTSTRAP || isHome(url)
    private fun isHome(url: String) =
        OfflineResourcePolicy.normalize(url)?.trimEnd('/') == OfflineRoutingPolicy.HOME.trimEnd('/')

    fun preparationScript(): String = """
        if (window === window.top && location.href === ${JSONObject.quote(BOOTSTRAP)}) {
          window.stop();
          setTimeout(async function () {
            try {
              if (navigator.serviceWorker) {
                const registrations = await navigator.serviceWorker.getRegistrations();
                await Promise.all(registrations.map(registration => registration.unregister()));
              }
              location.replace(${JSONObject.quote(OfflineRoutingPolicy.HOME)});
            } catch (error) {
              window.__UGamesOfflinePreparationError = String(error);
              window.__UGamesProtection.offlinePreparationFailed();
            }
          }, 0);
        }
    """.trimIndent()

    fun response(request: WebResourceRequest): WebResourceResponse {
        val url = request.url.toString()
        if (request.method != "GET") return OfflineWebPlayback.denied(404, "Not cached")
        if (OfflineResourcePolicy.normalize(url) ==
            BOOTSTRAP
        ) {
            return WebResourceResponse(
                "text/html",
                "utf-8",
                200,
                "OK",
                emptyMap(),
                "<!doctype html><title>UGames</title>".byteInputStream()
            )
        }
        if (isHome(
                url
            )
        ) {
            return WebResourceResponse(
                "text/html",
                "utf-8",
                200,
                "OK",
                emptyMap(),
                html.inputStream()
            )
        }
        val cover = covers[OfflineResourcePolicy.normalize(url)]
        if (cover != null && !request.isForMainFrame) {
            return try {
                WebResourceResponse(
                    cover.mimeType,
                    cover.encoding,
                    200,
                    "OK",
                    mapOf("Cache-Control" to "no-store"),
                    cover.file.inputStream()
                )
            } catch (_: Exception) {
                OfflineWebPlayback.denied(404, "Cover unavailable")
            }
        }
        return OfflineWebPlayback.denied(404, "Not cached")
    }
    companion object {
        const val BOOTSTRAP = "https://yandex.ru/games/.ugames-offline-bootstrap"
    }
}
