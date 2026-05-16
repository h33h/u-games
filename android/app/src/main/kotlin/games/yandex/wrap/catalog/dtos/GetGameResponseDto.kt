package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.Serializable

@Serializable
data class GetGameResponseDto(
    val game: DetailGameDto? = null,
)
