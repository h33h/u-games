package games.yandex.wrap.network

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.decodeFromJsonElement

class NetworkService(
    private val ktor: HttpClient,
    private val cookieHeaderProvider: () -> String = { "" },
    private val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    },
) {
    suspend fun <ResponseDto> execute(request: Request<ResponseDto>): ResponseDto {
        return execute(request, attempts = 1)
    }

    suspend fun <ResponseDto> execute(request: Request<ResponseDto>, attempts: Int): ResponseDto {
        val totalAttempts = attempts.coerceAtLeast(1)
        var lastError: Throwable? = null
        repeat(totalAttempts) { attempt ->
            exponentialBackoff(beforeAttempt = attempt)
            try {
                val response = makeRequest(request)
                return json.decodeFromJsonElement(request.serializer, response)
            } catch (error: Throwable) {
                if (!error.isTransientNetworkError || attempt == totalAttempts - 1) throw error
                lastError = error
            }
        }
        throw lastError ?: IllegalStateException("Network request failed without an error.")
    }

    private suspend fun makeRequest(request: Request<*>): JsonElement {
        return when (request.method) {
            HttpMethod.Get -> ktor.get(request.uri.toString()) {
                applyRequest(request)
            }.body()
            HttpMethod.Post -> ktor.post(request.uri.toString()) {
                applyRequest(request)
                contentType(ContentType.parse(request.contentType))
                request.jsonBody?.let { setBody(it) }
            }.body()
        }
    }

    private suspend fun exponentialBackoff(beforeAttempt: Int) {
        if (beforeAttempt == 0) return
        val retryIndex = (beforeAttempt - 1).coerceAtMost(6)
        val delayMs = 400L * (1L shl retryIndex)
        kotlinx.coroutines.delay(delayMs)
    }

    private fun io.ktor.client.request.HttpRequestBuilder.applyRequest(request: Request<*>) {
        for ((name, value) in request.query) parameter(name, value)
        for ((name, value) in request.headers) header(name, value)
        if (request.headers.keys.none { it.equals(HttpHeaders.Cookie, ignoreCase = true) }) {
            val cookieHeader = cookieHeaderProvider()
            if (cookieHeader.isNotBlank()) header(HttpHeaders.Cookie, cookieHeader)
        }
    }
}
