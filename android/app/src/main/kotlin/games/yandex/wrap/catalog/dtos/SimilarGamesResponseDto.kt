package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.Serializable

@Serializable
data class SimilarGamesResponseDto(
    val games: List<GameDto>? = null,
    val feed: List<FeedBlockDto> = emptyList(),
)
