package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.Serializable

@Serializable
data class PageInfoDto(
    val nextPageId: String? = null,
    val hasNextPage: Boolean? = null,
)
