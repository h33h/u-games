package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class TagsResponseDto(
    val tags: List<TagDto> = emptyList(),
)
