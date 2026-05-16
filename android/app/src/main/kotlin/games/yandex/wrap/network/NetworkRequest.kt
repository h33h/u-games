package games.yandex.wrap.network

import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import games.yandex.wrap.utils.Constants
import java.net.URI

enum class HttpMethod {
    Get,
    Post,
}

interface Request<ResponseDto> {
    val host: String
        get() = Constants.Network.host
    val path: String
    val method: HttpMethod
        get() = HttpMethod.Get
    val uri: URI
        get() = URI("https://$host$path")
    val serializer: KSerializer<ResponseDto>
    val query: Map<String, String>
        get() = emptyMap()
    val headers: Map<String, String>
        get() = emptyMap()
    val contentType: String
        get() = "application/json"
    val jsonBody: JsonObject?
        get() = null

    fun query(vararg pairs: Pair<String, String?>): Map<String, String> =
        pairs.mapNotNull { (name, value) -> value?.let { name to it } }.toMap()

    fun json(values: Map<String, Any?>): JsonObject =
        buildJsonObject {
            values.forEach { (name, value) -> put(name, value.toJsonElement()) }
        }

    fun json(vararg pairs: Pair<String, Any?>): JsonObject = json(mapOf(*pairs))
}

private fun Any?.toJsonElement(): JsonElement = when (this) {
    null -> JsonNull
    is JsonElement -> this
    is String -> JsonPrimitive(this)
    is Number -> JsonPrimitive(this)
    is Boolean -> JsonPrimitive(this)
    else -> JsonPrimitive(toString())
}
