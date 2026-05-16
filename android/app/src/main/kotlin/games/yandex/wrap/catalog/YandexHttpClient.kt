package games.yandex.wrap.catalog

import games.yandex.wrap.config.AppConfig
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.HttpHeaders
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.serialization.json.JsonObject
import java.net.URI

class YandexHttpClient(
    private val ktor: HttpClient,
    private val config: AppConfig,
) {
    suspend fun getJson(
        uri: URI,
        query: Map<String, String?> = emptyMap(),
        acceptLanguage: String = config.http.acceptLanguage,
        cookieHeader: String? = null,
    ): JsonObject = ktor.get(uri.toString()) {
        for ((name, value) in query) if (value != null) parameter(name, value)
        mobileHeaders(accept = "application/json,text/html;q=0.9", acceptLanguage = acceptLanguage)
        if (!cookieHeader.isNullOrEmpty()) header(HttpHeaders.Cookie, cookieHeader)
    }.body()

    suspend fun postJson(
        uri: URI,
        body: JsonObject,
        query: Map<String, String?> = emptyMap(),
        acceptLanguage: String = config.http.acceptLanguage,
        cookieHeader: String? = null,
    ): JsonObject = ktor.post(uri.toString()) {
        for ((name, value) in query) if (value != null) parameter(name, value)
        mobileHeaders(accept = "application/json", acceptLanguage = acceptLanguage)
        contentType(ContentType.Application.Json)
        setBody(body)
        if (!cookieHeader.isNullOrEmpty()) header(HttpHeaders.Cookie, cookieHeader)
    }.body()

    private fun io.ktor.client.request.HttpRequestBuilder.mobileHeaders(
        accept: String,
        acceptLanguage: String,
    ) {
        header(HttpHeaders.UserAgent, config.http.userAgent)
        header(HttpHeaders.Accept, accept)
        header(HttpHeaders.AcceptLanguage, acceptLanguage)
    }

}
