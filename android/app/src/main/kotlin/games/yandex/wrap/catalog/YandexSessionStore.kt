package games.yandex.wrap.catalog

import android.webkit.CookieManager
import games.yandex.wrap.config.AppConfig
import kotlinx.coroutines.delay

class YandexSessionStore(
    private val config: AppConfig,
    private val cookieManager: CookieManager = CookieManager.getInstance(),
) {
    suspend fun sessionCookieHeader(timeoutMs: Long = 3000): String {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val header = buildCookieHeader()
            if (header.contains("Session_id=")) return header
            delay(150)
        }
        return buildCookieHeader()
    }

    private fun buildCookieHeader(): String {
        val merged = LinkedHashMap<String, String>()
        for (origin in config.yandex.cookieOrigins()) {
            val raw = cookieManager.getCookie(origin).orEmpty()
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
        for (origin in config.yandex.cookieOrigins()) {
            val raw = cookieManager.getCookie(origin) ?: continue
            for (pair in raw.split(';')) {
                val name = pair.substringBefore('=').trim()
                if (name.isEmpty()) continue
                cookieManager.setCookie(origin, "$name=; Max-Age=0; Path=/")
            }
        }
        cookieManager.flush()
    }
}
