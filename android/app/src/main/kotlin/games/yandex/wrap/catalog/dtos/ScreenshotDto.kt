package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ScreenshotDto(
    @SerialName("prefix-url") val prefixUrl: String? = null,
    val url: String? = null,
)
