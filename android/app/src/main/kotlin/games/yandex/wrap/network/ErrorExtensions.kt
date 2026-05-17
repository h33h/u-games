package games.yandex.wrap.network

import java.io.IOException

class NetworkStatusException(
    val statusCode: Int,
    val responseBodySnippet: String,
) : Exception("HTTP $statusCode")

val Throwable.isTransientNetworkError: Boolean
    get() = this is IOException ||
        (this is NetworkStatusException && statusCode in setOf(408, 429, 500, 502, 503, 504))
