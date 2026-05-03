package games.yandex.wrap.webview

import android.webkit.CookieManager
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.http.Cookie
import io.ktor.http.CookieEncoding
import io.ktor.http.Url

/**
 * Bridges Ktor's CookiesStorage to Android's system WebView CookieManager so
 * that HTTP requests issued by the catalog client share the same session as
 * the in-app WebView (game iframe, auth screen). Without this, signing in via
 * the auth WebView wouldn't be visible to /games/ HTML fetch and the user
 * would appear anonymous to our profile loader.
 */
class AndroidWebViewCookieStorage : CookiesStorage {

    private val manager: CookieManager
        get() = CookieManager.getInstance()

    override suspend fun get(requestUrl: Url): List<Cookie> {
        val raw = manager.getCookie(requestUrl.toString()).orEmpty()
        if (raw.isEmpty()) return emptyList()
        return raw.split(';')
            .mapNotNull { pair ->
                val trimmed = pair.trim()
                val idx = trimmed.indexOf('=')
                if (idx <= 0) return@mapNotNull null
                Cookie(
                    name = trimmed.substring(0, idx),
                    value = trimmed.substring(idx + 1),
                    encoding = CookieEncoding.RAW,
                    domain = requestUrl.host,
                )
            }
    }

    override suspend fun addCookie(requestUrl: Url, cookie: Cookie) {
        val urlString = "${requestUrl.protocol.name}://${requestUrl.host}${requestUrl.encodedPath}"
        val pair = "${cookie.name}=${cookie.value}"
        manager.setCookie(urlString, pair)
        manager.flush()
    }

    override fun close() {}
}
