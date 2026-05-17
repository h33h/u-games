package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class FeedResponseDto(
    val feed: List<FeedBlockDto> = emptyList(),
    val items: List<GameDto> = emptyList(),
    val recentGames: List<GameDto> = emptyList(),
    val pageInfo: PageInfoDto? = null,
    val pageID: String? = null,
    val totalPages: Int? = null,
)
