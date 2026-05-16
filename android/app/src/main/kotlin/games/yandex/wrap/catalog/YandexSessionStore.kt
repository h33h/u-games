package games.yandex.wrap.catalog

import android.webkit.CookieManager
import games.yandex.wrap.config.AppConfig
import games.yandex.wrap.config.YandexHost
import kotlinx.coroutines.delay

class YandexSessionStore(
    private val config: AppConfig,
    private val cookieManager: CookieManager = CookieManager.getInstance(),
) {
    fun preferredYandexHost(): YandexHost = config.yandex.preferredHost

    suspend fun waitForSessionCookie(timeoutMs: Long = 3000) {
        val preferredHost = preferredYandexHost()
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val raw = cookieManager.getCookie(config.yandex.origin(preferredHost).toString()).orEmpty()
            if (raw.contains("Session_id=")) break
            delay(150)
        }
    }

    fun buildMergedYandexCookieHeader(): String {
        val merged = LinkedHashMap<String, String>()
        for (host in config.yandex.cookieDonorOrigins()) {
            val raw = cookieManager.getCookie(host).orEmpty()
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

    suspend fun clearSession() {
        for (host in config.yandex.cookieClearOrigins()) {
            val raw = cookieManager.getCookie(host) ?: continue
            for (pair in raw.split(';')) {
                val name = pair.substringBefore('=').trim()
                if (name.isEmpty()) continue
                cookieManager.setCookie(host, "$name=; Max-Age=0; Path=/")
            }
        }
        cookieManager.flush()
    }
}
