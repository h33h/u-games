package games.yandex.wrap.catalog

import java.io.IOException

data class HttpStatusException(val statusCode: Int) : IOException("HTTP $statusCode")

object NetworkErrorPolicy {
    fun isTransient(error: Throwable): Boolean = when (error) {
        is HttpStatusException -> error.statusCode in 500..599
        is IOException -> true
        else -> false
    }
}
