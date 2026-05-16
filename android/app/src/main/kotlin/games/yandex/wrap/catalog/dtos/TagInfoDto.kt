package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class TagInfoDto(
    @SerialName("games_count") val gamesCount: Int = 0,
)
