package dev.ugames

import android.webkit.ServiceWorkerClient
import android.webkit.ServiceWorkerController
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream
import org.json.JSONObject

class OfflineWebPlayback(private val game: SavedOfflineGame, private val filter: AdResourceFilter) {
    private val bootstrap = bootstrapUrl(game)

    fun allowsDocument(url: String): Boolean = OfflineResourcePolicy.normalize(url) == bootstrap ||
        (
            OfflineResourcePolicy.origin(url) == OfflineResourcePolicy.origin(game.entryUrl) &&
                GameNavigationPolicy.allowsFrame(url, game.entryUrl) && game.resource(url) != null
            )

    fun preparationScript(): String = """
        if (window === window.top && location.href === ${JSONObject.quote(bootstrap)}) {
          window.stop();
          setTimeout(async function () {
            try {
              if (navigator.serviceWorker) {
                const registrations = await navigator.serviceWorker.getRegistrations();
                await Promise.all(registrations.map(registration => registration.unregister()));
              }
              location.replace(${JSONObject.quote(game.entryUrl).replace("<", "\\u003c")});
            } catch (error) {
              window.__UGamesOfflinePreparationError = String(error);
              window.__UGamesProtection.offlinePreparationFailed();
            }
          }, 0);
        }
    """.trimIndent()

    fun response(request: WebResourceRequest): WebResourceResponse {
        val url = request.url.toString()
        if (filter.shouldBlock(url)) return denied(403, "Blocked advertising")
        if (request.method == "GET" && OfflineResourcePolicy.normalize(url) == bootstrap) {
            return WebResourceResponse(
                "text/html",
                "utf-8",
                200,
                "OK",
                emptyMap(),
                "<!doctype html><title>UGames</title>".byteInputStream()
            )
        }
        if (request.method != "GET" ||
            (request.isForMainFrame && !allowsDocument(url))
        ) {
            return denied(404, "Not downloaded")
        }
        if (OfflineResourcePolicy.isSdk(url)) {
            return WebResourceResponse(
                "application/javascript",
                "utf-8",
                200,
                "OK",
                mapOf("Access-Control-Allow-Origin" to "*"),
                ByteArrayInputStream(ByteArray(0))
            )
        }
        val resource = game.resource(url) ?: return denied(404, "Not downloaded")
        return try {
            WebResourceResponse(
                resource.mimeType,
                resource.encoding,
                200,
                "OK",
                OfflineResponseBody.headers(resource.headers),
                OfflineResponseBody.open(resource.file.inputStream(), resource.headers)
            )
        } catch (_: Exception) {
            denied(404, "Downloaded file missing")
        }
    }

    companion object {
        fun bootstrapUrl(game: SavedOfflineGame) =
            OfflineResourcePolicy.origin(game.entryUrl) + "/__ugames_offline_bootstrap__"

        fun denied(status: Int, reason: String) = WebResourceResponse(
            "text/plain",
            "utf-8",
            status,
            reason,
            mapOf("Access-Control-Allow-Origin" to "*", "Cache-Control" to "no-store"),
            ByteArrayInputStream(ByteArray(0))
        )

        fun configureServiceWorkers(
            playback: OfflineWebPlayback?,
            filter: AdResourceFilter,
            catalog: OfflineCatalogPlayback? = null
        ) {
            // Service-worker fetches have a separate network switch from WebView settings.
            ServiceWorkerController.getInstance().apply {
                serviceWorkerWebSettings.blockNetworkLoads = playback != null || catalog != null
                setServiceWorkerClient(object : ServiceWorkerClient() {
                    override fun shouldInterceptRequest(
                        request: WebResourceRequest
                    ): WebResourceResponse? =
                        playback?.response(request) ?: catalog?.response(request)
                            ?: if (filter.shouldBlock(request.url.toString())) {
                                denied(403, "Blocked advertising")
                            } else {
                                null
                            }
                })
            }
        }
    }
}
