package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class GetGameResponseDto(
    val game: DetailGameDto? = null,
)
