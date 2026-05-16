package games.yandex.wrap.catalog.dtos

import games.yandex.wrap.catalog.models.FeedBlock
import kotlinx.serialization.Serializable

@Serializable
data class FeedBlockDto(
    val type: String,
    val size: String? = null,
    val title: String = "",
    val items: List<GameDto> = emptyList(),
) {
    fun toDomain(): FeedBlock = FeedBlock(
        type = type,
        size = size,
        title = title,
        items = items.map(GameDto::toDomain),
    )
}
