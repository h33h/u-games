package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class FeedBlockDto(
    val type: String,
    val size: String? = null,
    val title: String = "",
    val items: List<GameDto> = emptyList(),
)
