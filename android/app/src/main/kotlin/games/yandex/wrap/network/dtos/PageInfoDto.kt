package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class PageInfoDto(
    val nextPageId: String? = null,
    val hasNextPage: Boolean? = null,
)
