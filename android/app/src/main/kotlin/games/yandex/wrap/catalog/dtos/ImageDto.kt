package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ImageDto(
    @SerialName("prefix-url") val prefixUrl: String? = null,
    val mainColor: String? = null,
)
