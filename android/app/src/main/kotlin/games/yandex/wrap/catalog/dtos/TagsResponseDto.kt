package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.Serializable

@Serializable
data class TagsResponseDto(
    val tags: List<TagDto> = emptyList(),
)
