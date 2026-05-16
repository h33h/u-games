package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class GameMediaDto(
    val cover: ImageDto? = null,
    val icon: ImageDto? = null,
    val videos: List<VideoDto> = emptyList(),
)
