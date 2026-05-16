package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class VideoDto(
    val mp4StreamUrl: String? = null,
)
