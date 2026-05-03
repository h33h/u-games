package games.yandex.wrap.webview

import android.graphics.Bitmap
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import okhttp3.Headers.Companion.toHeaders
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.ByteArrayInputStream
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * URL block-list (layer 3) + HTML response interception that injects PWA-CSS
 * directly into <head> of yandex.com/games HTML responses. This guarantees the
 * catalog chrome is hidden BEFORE the first paint — fixes the "intermediate
 * description page" flash that documentStart-script injection couldn't
 * fully eliminate on slow devices.
 *
 * Falls back to onPageStarted/onPageCommitVisible JS injection in case the
 * HTML interception is bypassed (e.g. cached pages).
 */
class AdBlockingClient(
    private val blockList: BlockList,
    private val scripts: InjectedScripts,
) : WebViewClient() {

    private val http: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
    }

    override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
        val url = request?.url?.toString() ?: return null
        if (blockList.isBlocked(url)) {
            return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(EMPTY_BYTES))
        }
        if (request.method.equals("GET", ignoreCase = true) && shouldRewriteHtml(url)) {
            return interceptYandexGamesHtml(url, request)
        }
        return null
    }

    private fun shouldRewriteHtml(url: String): Boolean {
        if (!url.startsWith("https://yandex.com/games/") && !url.startsWith("https://yandex.ru/games/")) return false
        if (!url.contains("/games/app/") && !url.contains("/games/play/")) return false
        return true
    }

    private fun interceptYandexGamesHtml(url: String, request: WebResourceRequest): WebResourceResponse? {
        return try {
            val rb = Request.Builder().url(url).get()
            request.requestHeaders.forEach { (k, v) ->
                if (!k.equals("Accept-Encoding", ignoreCase = true) &&
                    !k.equals("Range", ignoreCase = true) &&
                    !k.equals("Cookie", ignoreCase = true)
                ) {
                    rb.addHeader(k, v)
                }
            }
            CookieManager.getInstance().getCookie(url)?.let { cookie ->
                rb.addHeader("Cookie", cookie)
            }
            rb.addHeader("Accept-Encoding", "identity")
            val response = http.newCall(rb.build()).execute()
            val contentType = response.header("Content-Type") ?: "text/html"
            if (!contentType.contains("text/html", ignoreCase = true)) {
                response.close()
                return null
            }
            val charset = contentType.substringAfter("charset=", "utf-8")
                .substringBefore(';')
                .trim()
                .ifEmpty { "utf-8" }
            val raw = response.body?.string().orEmpty()
            response.close()
            val rewritten = injectStyleAndScripts(raw)
            val headers = HashMap<String, String>()
            for ((name, value) in response.headers) {
                if (name.equals("Content-Length", ignoreCase = true) ||
                    name.equals("Content-Encoding", ignoreCase = true) ||
                    name.equals("Transfer-Encoding", ignoreCase = true)
                ) continue
                headers[name] = value
            }
            WebResourceResponse(
                "text/html",
                charset,
                response.code,
                response.message.ifEmpty { "OK" },
                headers,
                ByteArrayInputStream(rewritten.toByteArray(charset(charset))),
            )
        } catch (_: IOException) {
            null
        } catch (_: IllegalStateException) {
            null
        }
    }

    private fun injectStyleAndScripts(html: String): String {
        val styleTag = "<style id=\"__yga_pwa__\">${scripts.pwaModeCss}</style>"
        val scriptTag = "<script id=\"__yga_inject__\">${scripts.honestPath};${scripts.pwaModeJs}</script>"
        val payload = styleTag + scriptTag
        val headIdx = html.indexOf("<head", ignoreCase = true)
        if (headIdx < 0) return payload + html
        val headOpen = html.indexOf('>', headIdx)
        if (headOpen < 0) return payload + html
        return html.substring(0, headOpen + 1) + payload + html.substring(headOpen + 1)
    }

    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
        super.onPageStarted(view, url, favicon)
        injectIfYandex(view, url)
    }

    override fun onPageCommitVisible(view: WebView?, url: String?) {
        super.onPageCommitVisible(view, url)
        injectIfYandex(view, url)
    }

    private fun injectIfYandex(view: WebView?, url: String?) {
        if (view == null || url == null) return
        when {
            url.startsWith("https://yandex.com/games") || url.startsWith("https://yandex.ru/games") -> {
                view.evaluateJavascript(scripts.mainFrameScript, null)
            }
            url.contains(".games.s3.yandex.net/") -> {
                view.evaluateJavascript(scripts.sdkStub, null)
            }
        }
    }

    private companion object {
        val EMPTY_BYTES = byteArrayOf()
    }
}

@Suppress("unused")
fun installDocumentStartScripts(webView: WebView, scripts: InjectedScripts) {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) return
    WebViewCompat.addDocumentStartJavaScript(
        webView,
        scripts.mainFrameScript,
        setOf("https://yandex.com", "https://yandex.ru"),
    )
    WebViewCompat.addDocumentStartJavaScript(
        webView,
        scripts.sdkStub,
        setOf("https://*.games.s3.yandex.net"),
    )
}
