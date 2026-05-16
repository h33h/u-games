package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class FeedResponseDto(
    val feed: List<FeedBlockDto> = emptyList(),
    val recentGames: List<GameDto> = emptyList(),
    val pageInfo: PageInfoDto? = null,
)
