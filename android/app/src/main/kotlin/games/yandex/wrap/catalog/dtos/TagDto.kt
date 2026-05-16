package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.Serializable

@Serializable
data class TagDto(
    val slug: String,
    val title: String,
    val info: TagInfoDto? = null,
)
