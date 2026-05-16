package games.yandex.wrap.catalog

import games.yandex.wrap.config.AppConfig
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.http.HttpHeaders
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URI
import java.util.concurrent.TimeUnit

class YandexHttpClient(
    private val ktor: HttpClient,
    private val config: AppConfig,
    private val okHttp: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build(),
) {
    suspend fun getJson(
        uri: URI,
        query: Map<String, String?> = emptyMap(),
        acceptLanguage: String = config.http.acceptLanguage,
    ): JsonObject = ktor.get(uri.toString()) {
        for ((name, value) in query) if (value != null) parameter(name, value)
        mobileHeaders(accept = "application/json,text/html;q=0.9", acceptLanguage = acceptLanguage)
    }.body()

    suspend fun getHtml(
        uri: URI,
        query: Map<String, String?> = emptyMap(),
        accept: String = "text/html",
        acceptLanguage: String = config.http.acceptLanguage,
        cookieHeader: String? = null,
    ): String = withContext(Dispatchers.IO) {
        val url = buildUrl(uri, query)
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", config.http.userAgent)
            .header("Accept", accept)
            .header("Accept-Language", acceptLanguage)
            .apply { if (!cookieHeader.isNullOrEmpty()) header("Cookie", cookieHeader) }
            .get()
            .build()
        okHttp.newCall(request).execute().use { response ->
            if (response.code in 500..599) throw HttpStatusException(response.code)
            response.body?.string().orEmpty()
        }
    }

    private fun io.ktor.client.request.HttpRequestBuilder.mobileHeaders(
        accept: String,
        acceptLanguage: String,
    ) {
        header(HttpHeaders.UserAgent, config.http.userAgent)
        header(HttpHeaders.Accept, accept)
        header(HttpHeaders.AcceptLanguage, acceptLanguage)
    }

    private fun buildUrl(uri: URI, query: Map<String, String?>): String {
        val filtered = query.filterValues { it != null }
        if (filtered.isEmpty()) return uri.toString()
        val encoded = filtered.entries.joinToString("&") { (name, value) ->
            "${name.urlEncoded()}=${value.orEmpty().urlEncoded()}"
        }
        return "${uri}?$encoded"
    }
}

private fun String.urlEncoded(): String =
    java.net.URLEncoder.encode(this, Charsets.UTF_8.name())
